all: build

build:
	@docker build --tag=jps64/nextcloud .

release: build
	@docker build --tag=jps64/nextcloud:$(shell cat VERSION) .
