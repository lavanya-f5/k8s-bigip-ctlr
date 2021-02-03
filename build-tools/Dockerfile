ARG GO_CONTAINER=golang:1.15-buster
FROM $GO_CONTAINER AS builder
# Controller install steps
COPY entrypoint.builder.sh /entrypoint.sh
COPY requirements.txt /tmp/requirements.txt
COPY requirements.docs.txt /tmp/requirements.docs.txt
RUN pip install --no-cache-dir --upgrade pip==20.0.2 && \
    pip install --no-cache-dir setuptools flake8 virtualenv && \
	pip install --no-cache-dir -r /tmp/requirements.txt && \
	pip install --no-cache-dir -r /tmp/requirements.docs.txt && \
	go get github.com/wadey/gocovmerge && \
	go get golang.org/x/tools/cmd/cover && \
	go get github.com/mattn/goveralls && \
	go get github.com/onsi/ginkgo/ginkgo && \
	go get github.com/onsi/gomega && \
	chmod 755 /entrypoint.sh

COPY --from=gosu/assets /opt/gosu /opt/gosu
RUN set -x \
    && /opt/gosu/gosu.install.sh \
    && rm -fr /opt/gosu

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "/bin/bash" ]
