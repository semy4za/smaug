cc		= GCC
CFLAGS	= -std=c11 -fPIC -Wall -Wextra -O2 -I./include
LDFLAGS = -shared

# Backend C completo (f64 + i64)
SRCS = src/smaug_core.c src/smaug_ops_f64.c src/smaug_ops_i64.c

TARGET = build/libsmaug_math.so

$(TARGET): $(SRCS) | build
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	@echo "Compilado: $@	-- OK"

build:
	mkdir -p build

clean:
	rm -rf build

.PHONY : clean
