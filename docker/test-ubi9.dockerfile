ARG base_image=swift:5.8-rhel-ubi9
FROM $base_image
# needed to do again after FROM due to docker limitation
ARG swift_version
ARG ubuntu_version

# dependencies
RUN yum install -y --allowerasing \
    curl \
    gcc \
    gcc-c++ \
    make \
    gpg
COPY ./scripts/install-libarchive.sh /
RUN /install-libarchive.sh

# tools
RUN mkdir -p $HOME/.tools
RUN echo 'export PATH="$HOME/.tools:$PATH"' >> $HOME/.profile
