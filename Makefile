DESTDIR?=/
PREFIX=/usr

bin/dbus-systemd-dispatcher: main.go
	mkdir -p bin
	go build -ldflags '-s'
	mv dbus-systemd-dispatcher bin

bin/sleep.so: plugins/sleep.go
	mkdir -p bin
	go build -buildmode=plugin plugins/sleep.go
	mv sleep.so bin

bin/lock.so: plugins/lock.go
	mkdir -p bin
	go build -buildmode=plugin plugins/lock.go
	mv lock.so bin

plugins: bin/sleep.so bin/lock.so

build: bin/dbus-systemd-dispatcher

install: build
	@install -Dm755 bin/dbus-systemd-dispatcher ${DESTDIR}${PREFIX}/lib/dbus-systemd-dispatcher
	@install -Dm644 dbus-systemd-dispatcher.service ${DESTDIR}${PREFIX}/lib/systemd/user/dbus-systemd-dispatcher.service
	@install -Dm644 dbus-systemd-dispatcher.service ${DESTDIR}${PREFIX}/lib/systemd/system/dbus-systemd-dispatcher.service

.PHONY: build install plugins
