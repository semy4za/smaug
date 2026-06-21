CC      = gcc
CFLAGS  = -std=c11 -fPIC -Wall -Wextra -O2 -I./include
LDFLAGS = -shared

# Backend C completo (f64 + i64 + bool + string)
SRCS = src/smaug_core.c src/smaug_ops_f64.c src/smaug_ops_i64.c src/smaug_ops_bool.c src/smaug_str.c src/smaug_ops_str.c src/smaug_csv.c src/smaug_json.c src/smaug_datetime.c src/smaug_ops_window.c

TARGET = build/libsmaug.so

# Flags para os binários de teste (debug, sem -fPIC/-shared)
TEST_CFLAGS = -std=c11 -g -O0 -Wall -Wextra -I./include

# === Listas de teste centralizadas (FONTE ÚNICA) ============================
# Adicionar um teste = editar AQUI e em mais nenhum lugar. Os alvos test,
# valgrind e test-lua iteram sobre estas listas.
#   C_TESTS_PLAIN : testes C linkados normalmente (contra os SRCS).
#   C_TEST_WRAP   : teste(s) que exigem -Wl,--wrap (falha de alocação).
#   LUA_TESTS     : suítes do frontend Lua.
C_TESTS_PLAIN = test_alloc test_ops test_ops_edge test_bool test_bool_lifecycle test_string test_cow \
                test_io_c test_datetime_c test_ops_window
C_TEST_WRAP   = test_allocfail
C_TEST_STRESS = test_stress
LUA_TESTS_SERIES  = series/test_constructors series/test_access series/test_reduce \
                    series/test_stat series/test_window series/test_predicates \
                    series/test_selection series/test_str series/test_dt series/test_categorical
LUA_TESTS_DATASET = dataset/test_core dataset/test_relational dataset/test_stat \
                    dataset/test_io_support
LUA_TESTS_IO      = io/test_csv io/test_json
LUA_TESTS_PROPS   = props/test_props props/test_integration
LUA_TESTS         = $(LUA_TESTS_SERIES) $(LUA_TESTS_DATASET) $(LUA_TESTS_IO) $(LUA_TESTS_PROPS)
WRAP_FLAGS    = -Wl,--wrap=malloc -Wl,--wrap=realloc -Wl,--wrap=calloc -Wl,--wrap=strdup

$(TARGET): $(SRCS) | build
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	@echo "Compilado: $@	-- OK"

build:
	mkdir -p build

# Compila e roda os testes em C (plain + wrap), iterando sobre as listas.
test: build
	@for t in $(C_TESTS_PLAIN); do \
		echo "  CC    $$t"; \
		$(CC) $(TEST_CFLAGS) tests/c/$$t.c $(SRCS) -lm -o build/$$t || exit 1; \
	done
	@for t in $(C_TEST_WRAP); do \
		echo "  CC    $$t (--wrap)"; \
		$(CC) $(TEST_CFLAGS) $(WRAP_FLAGS) tests/c/$$t.c $(SRCS) -lm -o build/$$t || exit 1; \
	done
	@for t in $(C_TESTS_PLAIN) $(C_TEST_WRAP); do \
		echo "  RUN   $$t"; ./build/$$t || exit 1; \
	done

# Compila e roda os testes de stress (N grande; mais lento que make test)
test-stress: build
	@for t in $(C_TEST_STRESS); do \
		echo "  CC    $$t"; \
		$(CC) $(TEST_CFLAGS) tests/c/$$t.c $(SRCS) -lm -o build/$$t || exit 1; \
	done
	@for t in $(C_TEST_STRESS); do \
		echo "  RUN   $$t"; ./build/$$t || exit 1; \
	done

# Roda todos os testes C sob Valgrind (requer valgrind instalado)
valgrind: test test-stress
	@for t in $(C_TESTS_PLAIN) $(C_TEST_WRAP) $(C_TEST_STRESS); do \
		echo "  VALGRIND $$t"; \
		valgrind --leak-check=full --error-exitcode=1 ./build/$$t || exit 1; \
	done

# Smoke test do frontend Lua (requer luajit e a .so compilada)
test-lua: $(TARGET)
	@for t in $(LUA_TESTS); do \
		luajit tests/$$t.lua || exit 1; \
	done

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

.PHONY : clean test test-stress valgrind test-lua coverage manifest verify
