CC      = gcc
CFLAGS  = -std=c11 -fPIC -Wall -Wextra -O2 -I./include
LDFLAGS = -shared

# Backend C completo (f64 + i64 + bool + string)
SRCS = src/smaug_core.c src/smaug_ops_f64.c src/smaug_ops_i64.c src/smaug_ops_bool.c src/smaug_str.c src/smaug_ops_str.c src/smaug_csv.c src/smaug_json.c src/smaug_datetime.c

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
                test_io_c test_datetime_c
C_TEST_WRAP   = test_allocfail
C_TEST_STRESS = test_stress
LUA_TESTS     = test_series test_i64 test_bool_dtype test_edge test_special test_fillna \
                test_string test_str_tier_b test_str_tier_c test_props \
                test_datetime test_categorical test_completeness test_dt_extended \
                test_dataset test_dataset_ops test_series_ops \
                test_groupby test_concat test_join \
                test_rolling_series test_enrich test_stats test_predicates test_access test_duplicates \
                test_io test_io_real
WRAP_FLAGS    = -Wl,--wrap=malloc -Wl,--wrap=realloc

$(TARGET): $(SRCS) | build
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	@echo "Compilado: $@	-- OK"

build:
	mkdir -p build

# Compila e roda os testes em C (plain + wrap), iterando sobre as listas.
test: build
	@for t in $(C_TESTS_PLAIN); do \
		echo "  CC    $$t"; \
		$(CC) $(TEST_CFLAGS) tests/$$t.c $(SRCS) -lm -o build/$$t || exit 1; \
	done
	@for t in $(C_TEST_WRAP); do \
		echo "  CC    $$t (--wrap)"; \
		$(CC) $(TEST_CFLAGS) $(WRAP_FLAGS) tests/$$t.c $(SRCS) -lm -o build/$$t || exit 1; \
	done
	@for t in $(C_TESTS_PLAIN) $(C_TEST_WRAP); do \
		echo "  RUN   $$t"; ./build/$$t || exit 1; \
	done

# Compila e roda os testes de stress (N grande; mais lento que make test)
test-stress: build
	@for t in $(C_TEST_STRESS); do \
		echo "  CC    $$t"; \
		$(CC) $(TEST_CFLAGS) tests/$$t.c $(SRCS) -lm -o build/$$t || exit 1; \
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
