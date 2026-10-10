.PHONY: build run app install uninstall clean

build:
	swift build

run:
	swift run

app:
	./scripts/build-app.sh

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

clean:
	rm -rf .build dist
