ARG base_image=amazonlinux:2
FROM $base_image

RUN yum install -y curl util-linux gpg
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> $HOME/.profile
