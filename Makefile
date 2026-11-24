# FriCAS container on STRIX. See README.md.
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

SBCL_TAG   ?= sbcl-2.6.10
SBCL_OPTS  ?= --fancy --dynamic-space-size=8Gb
FRICAS_REF ?= 1.4.0
JOBS       ?= 12
RUN_CHECK  ?= 1
IMAGE      ?= fricas:$(FRICAS_REF)-$(SBCL_TAG)
NAME       ?= fricas
WORK       ?= $(HOME)/fricas-work
DEV        ?= $(HOME)/fricas-dev

.PHONY: build run stop restart shell fricas sbcl check check-log status

# The image being replaced keeps a "-prev" tag, for rollback (make restart IMAGE=...-prev).
build:
	-docker image inspect $(IMAGE) >/dev/null 2>&1 && docker tag $(IMAGE) $(IMAGE)-prev
	docker build \
	  --build-arg SBCL_TAG=$(SBCL_TAG) --build-arg "SBCL_OPTS=$(SBCL_OPTS)" \
	  --build-arg FRICAS_REF=$(FRICAS_REF) --build-arg JOBS=$(JOBS) \
	  --build-arg RUN_CHECK=$(RUN_CHECK) \
	  --build-arg UID=$$(id -u) --build-arg GID=$$(id -g) \
	  --progress=plain -t $(IMAGE) . 2>&1 | tee build-$(FRICAS_REF)-$(SBCL_TAG).log

run:
	mkdir -p $(WORK)/runs $(WORK)/host-runs $(DEV)/src $(DEV)/build $(DEV)/install
	docker run -d --name $(NAME) --hostname $(NAME) --restart unless-stopped \
	  -v $(WORK):/home/fricas/work -v $(DEV):/home/fricas/dev \
	  $(IMAGE)

stop:
	-docker stop $(NAME)
	-docker rm $(NAME)

restart: stop run

shell:
	docker exec -it $(NAME) bash

fricas:
	docker exec -it $(NAME) rlwrap fricas -nosman

sbcl:
	docker exec -it $(NAME) rlwrap sbcl

# Quick smoke test of the running container
check:
	docker exec $(NAME) sbcl --noinform --non-interactive \
	  --eval '(format t "SBCL ~a, heap ~,1f GiB~%" (lisp-implementation-version) (/ (sb-ext:dynamic-space-size) (expt 2.0 30)))'
	printf '%s\n' ')set quit unprotected' \
	  ')lisp (format t "FriCAS on SBCL ~a, heap ~,1f GiB~%" (lisp-implementation-version) (/ (sb-ext:dynamic-space-size) (expt 2.0 30)))' \
	  'factor(2^64-1)' \
	  'integrate(exp(-x^2), x = %minusInfinity..%plusInfinity)' \
	  ')quit' | docker exec -i $(NAME) fricas -nosman
	-docker exec $(NAME) cat /opt/fricas/release/make-check.status

# Tail of the FriCAS test-suite log made during `make build`
check-log:
	docker exec $(NAME) tail -n 40 /opt/fricas/release/make-check.log

status:
	docker ps -a --filter name=^/$(NAME)$$
	docker images fricas
