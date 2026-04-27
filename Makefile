PRIV_DIR    = $(MIX_APP_PATH)/priv
NIF_LIB     = $(PRIV_DIR)/image_ocr_nif.so

ERTS_INCLUDE_DIR ?= $(shell erl -noshell -eval 'io:format("~ts/erts-~ts/include/", [code:root_dir(), erlang:system_info(version)]).' -s init stop)

PKG_CFLAGS  = $(shell pkg-config --cflags tesseract lept)
PKG_LDLIBS  = $(shell pkg-config --libs tesseract lept)

CXX        ?= c++
CXXFLAGS   ?= -O3 -fPIC -std=c++17 -Wall -Wextra
CPPFLAGS   += -I"$(ERTS_INCLUDE_DIR)" $(PKG_CFLAGS)
LDFLAGS    +=
LDLIBS     += $(PKG_LDLIBS)

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  LDFLAGS += -dynamiclib -undefined dynamic_lookup -flat_namespace
else
  LDFLAGS += -shared
endif

SRC = c_src/image_ocr_nif.cc

all: check_version $(NIF_LIB)

check_version:
	@pkg-config --atleast-version=5.0.0 tesseract || \
	  (echo "ERROR: image_ocr requires tesseract >= 5.0.0 (found $$(pkg-config --modversion tesseract 2>/dev/null || echo none))"; exit 1)

$(NIF_LIB): $(SRC)
	@mkdir -p $(PRIV_DIR)
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) $(LDFLAGS) $(SRC) -o $@ $(LDLIBS)

clean:
	rm -f $(NIF_LIB)

.PHONY: all clean check_version
