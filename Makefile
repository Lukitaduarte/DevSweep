.PHONY: app install test clean

app:
	./scripts/build-app.sh

install:
	./scripts/build-app.sh --install

test:
	swift test

clean:
	rm -rf .build build
