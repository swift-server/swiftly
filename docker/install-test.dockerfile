ARG base_image=ubuntu:jammy
FROM $base_image

# set as UTF-8
RUN apt-get update && apt-get install -y locales locales-all sqlite3
ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

# dependencies
RUN apt-get update --fix-missing && apt-get install -y curl gpg
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> $HOME/.profile
