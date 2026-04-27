// image_ocr NIF: thin wrapper around tesseract::TessBaseAPI.
//
// Concurrency model:
//   * Each %ImageOcr{} owns one TessBaseAPI*. TessBaseAPI is NOT safe for
//     concurrent use on the same instance. We hold a per-resource ErlNifMutex
//     so accidental sharing degrades to serialization rather than UB.
//   * For real parallelism, callers create one instance per worker (see
//     ImageOcr.Pool). All recognition entry points are dirty-CPU NIFs.

#include <cstring>
#include <string>

#include <erl_nif.h>
#include <tesseract/baseapi.h>
#include <tesseract/publictypes.h>
#include <tesseract/resultiterator.h>

namespace {

ErlNifResourceType* TESS_RESOURCE_TYPE = nullptr;

struct TessResource {
  tesseract::TessBaseAPI* api;
  ErlNifMutex* mutex;
};

void tess_resource_dtor(ErlNifEnv*, void* obj) {
  auto* r = static_cast<TessResource*>(obj);
  if (r->api) {
    r->api->End();
    delete r->api;
    r->api = nullptr;
  }
  if (r->mutex) {
    enif_mutex_destroy(r->mutex);
    r->mutex = nullptr;
  }
}

ERL_NIF_TERM mk_atom(ErlNifEnv* env, const char* name) {
  ERL_NIF_TERM atom;
  if (!enif_make_existing_atom(env, name, &atom, ERL_NIF_LATIN1)) {
    atom = enif_make_atom(env, name);
  }
  return atom;
}

ERL_NIF_TERM mk_ok(ErlNifEnv* env, ERL_NIF_TERM value) {
  return enif_make_tuple2(env, mk_atom(env, "ok"), value);
}

ERL_NIF_TERM mk_error(ErlNifEnv* env, const char* reason) {
  return enif_make_tuple2(env, mk_atom(env, "error"), mk_atom(env, reason));
}

bool get_iolist_string(ErlNifEnv* env, ERL_NIF_TERM term, std::string* out) {
  ErlNifBinary bin;
  if (enif_inspect_iolist_as_binary(env, term, &bin)) {
    out->assign(reinterpret_cast<const char*>(bin.data), bin.size);
    return true;
  }
  return false;
}

tesseract::PageSegMode psm_from_int(int v) {
  if (v < 0 || v > tesseract::PSM_COUNT - 1) return tesseract::PSM_AUTO;
  return static_cast<tesseract::PageSegMode>(v);
}

// init_nif(language :: binary, datapath :: binary | nil, psm :: integer)
ERL_NIF_TERM init_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 3) return enif_make_badarg(env);

  std::string language;
  if (!get_iolist_string(env, argv[0], &language) || language.empty()) {
    return mk_error(env, "invalid_language");
  }

  std::string datapath;
  bool have_datapath = false;
  if (!enif_is_atom(env, argv[1])) {
    if (!get_iolist_string(env, argv[1], &datapath)) {
      return mk_error(env, "invalid_datapath");
    }
    have_datapath = true;
  }

  int psm_int;
  if (!enif_get_int(env, argv[2], &psm_int)) return enif_make_badarg(env);

  auto* api = new tesseract::TessBaseAPI();
  int rc = api->Init(have_datapath ? datapath.c_str() : nullptr,
                     language.c_str(),
                     tesseract::OEM_DEFAULT);
  if (rc != 0) {
    delete api;
    return mk_error(env, "init_failed");
  }
  api->SetPageSegMode(psm_from_int(psm_int));
  // Suppress Tesseract's noisy "Estimating resolution as N" stderr chatter.
  // Callers can override via the `:variables` option if they need it back.
  api->SetVariable("debug_file", "/dev/null");

  auto* res = static_cast<TessResource*>(
      enif_alloc_resource(TESS_RESOURCE_TYPE, sizeof(TessResource)));
  res->api = api;
  res->mutex = enif_mutex_create(const_cast<char*>("image_ocr.api"));

  ERL_NIF_TERM term = enif_make_resource(env, res);
  enif_release_resource(res);
  return mk_ok(env, term);
}

// set_variable_nif(api, key :: binary, value :: binary)
ERL_NIF_TERM set_variable_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 3) return enif_make_badarg(env);

  TessResource* res;
  if (!enif_get_resource(env, argv[0], TESS_RESOURCE_TYPE, (void**)&res)) {
    return enif_make_badarg(env);
  }

  std::string key, value;
  if (!get_iolist_string(env, argv[1], &key) ||
      !get_iolist_string(env, argv[2], &value)) {
    return enif_make_badarg(env);
  }

  enif_mutex_lock(res->mutex);
  bool ok = res->api->SetVariable(key.c_str(), value.c_str());
  enif_mutex_unlock(res->mutex);

  return ok ? mk_atom(env, "ok") : mk_error(env, "unknown_variable");
}

// recognize_nif(api, pixel_binary, width, height, bytes_per_pixel, bytes_per_line)
ERL_NIF_TERM recognize_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 6) return enif_make_badarg(env);

  TessResource* res;
  if (!enif_get_resource(env, argv[0], TESS_RESOURCE_TYPE, (void**)&res)) {
    return enif_make_badarg(env);
  }

  ErlNifBinary pixels;
  if (!enif_inspect_binary(env, argv[1], &pixels)) return enif_make_badarg(env);

  int width, height, bpp, bpl;
  if (!enif_get_int(env, argv[2], &width) ||
      !enif_get_int(env, argv[3], &height) ||
      !enif_get_int(env, argv[4], &bpp) ||
      !enif_get_int(env, argv[5], &bpl)) {
    return enif_make_badarg(env);
  }

  if (width <= 0 || height <= 0 || bpp < 1 || bpp > 4 || bpl < width * bpp) {
    return mk_error(env, "invalid_image_geometry");
  }
  if (pixels.size < static_cast<size_t>(bpl) * static_cast<size_t>(height)) {
    return mk_error(env, "insufficient_pixel_data");
  }

  enif_mutex_lock(res->mutex);
  res->api->SetImage(pixels.data, width, height, bpp, bpl);
  char* utf8 = res->api->GetUTF8Text();
  // Drop image-related buffers; keeps memory bounded between calls.
  res->api->Clear();
  enif_mutex_unlock(res->mutex);

  if (!utf8) return mk_error(env, "recognition_failed");

  size_t len = std::strlen(utf8);
  ERL_NIF_TERM bin;
  unsigned char* buf = enif_make_new_binary(env, len, &bin);
  std::memcpy(buf, utf8, len);
  delete[] utf8;
  return mk_ok(env, bin);
}

// recognize_with_boxes_nif(api, pixel_binary, width, height, bpp, bpl)
ERL_NIF_TERM recognize_with_boxes_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 6) return enif_make_badarg(env);

  TessResource* res;
  if (!enif_get_resource(env, argv[0], TESS_RESOURCE_TYPE, (void**)&res)) {
    return enif_make_badarg(env);
  }

  ErlNifBinary pixels;
  if (!enif_inspect_binary(env, argv[1], &pixels)) return enif_make_badarg(env);

  int width, height, bpp, bpl;
  if (!enif_get_int(env, argv[2], &width) ||
      !enif_get_int(env, argv[3], &height) ||
      !enif_get_int(env, argv[4], &bpp) ||
      !enif_get_int(env, argv[5], &bpl)) {
    return enif_make_badarg(env);
  }

  if (width <= 0 || height <= 0 || bpp < 1 || bpp > 4 || bpl < width * bpp) {
    return mk_error(env, "invalid_image_geometry");
  }
  if (pixels.size < static_cast<size_t>(bpl) * static_cast<size_t>(height)) {
    return mk_error(env, "insufficient_pixel_data");
  }

  enif_mutex_lock(res->mutex);
  res->api->SetImage(pixels.data, width, height, bpp, bpl);
  int rc = res->api->Recognize(nullptr);
  if (rc != 0) {
    res->api->Clear();
    enif_mutex_unlock(res->mutex);
    return mk_error(env, "recognition_failed");
  }

  ERL_NIF_TERM list = enif_make_list(env, 0);
  tesseract::ResultIterator* it = res->api->GetIterator();
  if (it != nullptr) {
    const tesseract::PageIteratorLevel level = tesseract::RIL_WORD;
    do {
      char* word = it->GetUTF8Text(level);
      if (word == nullptr) continue;
      float conf = it->Confidence(level);
      int x1, y1, x2, y2;
      it->BoundingBox(level, &x1, &y1, &x2, &y2);

      size_t wlen = std::strlen(word);
      ERL_NIF_TERM word_bin;
      unsigned char* wbuf = enif_make_new_binary(env, wlen, &word_bin);
      std::memcpy(wbuf, word, wlen);
      delete[] word;

      ERL_NIF_TERM keys[3] = {
          mk_atom(env, "text"),
          mk_atom(env, "confidence"),
          mk_atom(env, "bbox")};
      ERL_NIF_TERM bbox = enif_make_tuple4(
          env,
          enif_make_int(env, x1),
          enif_make_int(env, y1),
          enif_make_int(env, x2),
          enif_make_int(env, y2));
      ERL_NIF_TERM values[3] = {
          word_bin,
          enif_make_double(env, static_cast<double>(conf)),
          bbox};
      ERL_NIF_TERM map;
      enif_make_map_from_arrays(env, keys, values, 3, &map);
      list = enif_make_list_cell(env, map, list);
    } while (it->Next(level));
    delete it;
  }
  res->api->Clear();
  enif_mutex_unlock(res->mutex);

  // Reverse list to preserve reading order.
  ERL_NIF_TERM reversed;
  enif_make_reverse_list(env, list, &reversed);
  return mk_ok(env, reversed);
}

// tesseract_version_nif() :: binary
ERL_NIF_TERM tesseract_version_nif(ErlNifEnv* env, int, const ERL_NIF_TERM[]) {
  const char* v = tesseract::TessBaseAPI::Version();
  size_t len = std::strlen(v);
  ERL_NIF_TERM bin;
  unsigned char* buf = enif_make_new_binary(env, len, &bin);
  std::memcpy(buf, v, len);
  return bin;
}

int load(ErlNifEnv* env, void**, ERL_NIF_TERM) {
  ErlNifResourceFlags flags =
      static_cast<ErlNifResourceFlags>(ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER);
  TESS_RESOURCE_TYPE = enif_open_resource_type(
      env, nullptr, "image_ocr_tess_api", tess_resource_dtor, flags, nullptr);
  return TESS_RESOURCE_TYPE == nullptr ? -1 : 0;
}

ErlNifFunc nif_funcs[] = {
    {"init_nif", 3, init_nif, 0},
    {"set_variable_nif", 3, set_variable_nif, 0},
    {"recognize_nif", 6, recognize_nif, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"recognize_with_boxes_nif", 6, recognize_with_boxes_nif, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"tesseract_version_nif", 0, tesseract_version_nif, 0},
};

}  // namespace

ERL_NIF_INIT(Elixir.ImageOcr.Nif, nif_funcs, load, nullptr, nullptr, nullptr)
