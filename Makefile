CC      = gcc
CFLAGS	= -std=c11 -fPIC -Wall -Wextra -O2 -I./include
LDFLAGS = -shared

# Backend C completo (f64 + i64 + bool)
SRCS = src/smaug_core.c src/smaug_ops_f64.c src/smaug_ops_i64.c src/smaug_ops_bool.c

TARGET = build/libsmaug_math.so

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
	./build/test_alloc
	./build/test_ops
	./build/test_bool

# Roda os testes sob Valgrind (requer valgrind instalado)
valgrind: test
	valgrind --leak-check=full --error-exitcode=1 ./build/test_alloc
	valgrind --leak-check=full --error-exitcode=1 ./build/test_ops
	valgrind --leak-check=full --error-exitcode=1 ./build/test_bool

# Smoke test do frontend Lua (requer luajit e a .so compilada)
test-lua: $(TARGET)
	luajit tests/test_series.lua

clean:
	rm -rf build

.PHONY : clean test valgrind test-lua
