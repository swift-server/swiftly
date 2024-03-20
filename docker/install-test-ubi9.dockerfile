ARG base_image=redhat/ubi9:latest
FROM $base_image

RUN yum install --allowerasing -y curl gcc-c++ gpg
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> $HOME/.profile
