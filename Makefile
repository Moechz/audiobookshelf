# Makefile - 便捷入口（实际逻辑都在 build.sh）
.PHONY: all fetch stage deb verify clean distclean info

all: package

package:
	./build.sh

fetch:
	./build.sh fetch

stage:
	./build.sh stage

deb:
	./build.sh deb

verify:
	./build.sh verify

clean:
	./build.sh clean

distclean:
	./build.sh distclean

info:
	./build.sh info
