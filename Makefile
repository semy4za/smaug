CC      = gcc
CFLAGS	= -std=c11 -fPIC -Wall -Wextra -O2 -I./include
LDFLAGS = -shared

# Backend C completo (f64 + i64 + bool)
SRCS = src/smaug_core.c src/smaug_ops_f64.c src/smaug_ops_i64.c src/smaug_ops_bool.c src/smaug_ops_str.c

TARGET = build/libsmaug.so

# Flags para os binários de teste (debug, sem -fPIC/-shared)
TEST_CFLAGS = -std=c11 -g -O0 -Wall -Wextra -I./include

$(TARGET): $(SRCS) | build
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	@echo "Compilado: $@	-- OK"

build:
	mkdir -p build

# Compila e roda os testes em C
test: build
	$(CC) $(TEST_CFLAGS) tests/test_alloc.c $(SRCS) -lm -o build/test_alloc
	$(CC) $(TEST_CFLAGS) tests/test_ops.c   $(SRCS) -lm -o build/test_ops
	$(CC) $(TEST_CFLAGS) tests/test_bool.c  $(SRCS) -lm -o build/test_bool
	$(CC) $(TEST_CFLAGS) tests/test_string.c $(SRCS) -lm -o build/test_string
	$(CC) $(TEST_CFLAGS) -Wl,--wrap=malloc -Wl,--wrap=realloc tests/test_allocfail.c $(SRCS) -lm -o build/test_allocfail
	./build/test_alloc
	./build/test_ops
	./build/test_bool
	./build/test_string
	./build/test_allocfail

# Roda os testes sob Valgrind (requer valgrind instalado)
valgrind: test
	valgrind --leak-check=full --error-exitcode=1 ./build/test_alloc
	valgrind --leak-check=full --error-exitcode=1 ./build/test_ops
	valgrind --leak-check=full --error-exitcode=1 ./build/test_bool
	valgrind --leak-check=full --error-exitcode=1 ./build/test_string
	valgrind --leak-check=full --error-exitcode=1 ./build/test_allocfail

# Smoke test do frontend Lua (requer luajit e a .so compilada)
test-lua: $(TARGET)
	luajit tests/test_series.lua
	luajit tests/test_dataset.lua
	luajit tests/test_edge.lua
	luajit tests/test_special.lua
	luajit tests/test_fillna.lua
	luajit tests/test_props.lua
	luajit tests/test_i64.lua

# Mede cobertura do backend C e gera docs/COVERAGE.md (requer gcov; só Linux)
coverage:
	bash scripts/make_coverage.sh

# Gera docs/MANIFEST.txt (sha256 + linhas de cada arquivo versionável)
manifest:
	bash scripts/make_manifest.sh

# Verifica a árvore atual contra o MANIFEST.txt (detecta perda/divergência)
verify:
	@bash scripts/make_manifest.sh >/dev/null
	@git diff --stat docs/MANIFEST.txt 2>/dev/null || true
	@echo "MANIFEST regenerado; compare com a versão anterior (git diff) para detectar mudanças."

clean:
	rm -rf build

.PHONY : clean test valgrind test-lua coverage manifest verify
