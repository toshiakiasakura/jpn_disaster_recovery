# quay.io is the current home of the Jupyter docker-stacks images and, unlike the
# legacy Docker Hub repo (amd64-only), publishes multi-arch manifests including
# linux/aarch64 for Apple Silicon (Mac ARM64). The bare r-4.3.1 tag auto-selects
# the correct architecture at pull time.
FROM quay.io/jupyter/datascience-notebook:r-4.3.1

WORKDIR /workdir
EXPOSE 8888

ENV DEVCONTAINER=TRUE

### R package installation.
# One solve for every conda-provided R package. The CRAN-pinned installs on the
# next line write into this same .libPaths() without conda knowing, so a *later*
# conda solve could relink its own r-ggplot2 over the 4.0.1 pin. Keeping all
# conda packages here means the CRAN pins are always applied last.
# r-languageserver backs the VS Code R extension.
# cmake is only needed to build RcppParallel (>= 6.1.1, required by qs2) from
# source; conda-forge has no r-qs2 and only RcppParallel 5.x.
# ungroup (pclm, splits 5-year age bands into single years) is CRAN-only; it
# pulls in RcppEigen, pbapply and Rdpack.
# font-ttf-noto-cjk provides "Noto Sans CJK JP" so figures can show Japanese text.
RUN mamba install -c conda-forge r-tidyverse=2.0.0 r-glue=1.8.0 r-lubridate=1.9.4 r-magrittr=2.0.4 r-readxl=1.4.5 r-languageserver=0.3.16 cmake font-ttf-noto-cjk=2.004 -y
RUN Rscript -e 'install.packages("remotes", repos="https://cloud.r-project.org"); remotes::install_version("scales", "1.4.0", repos="https://cloud.r-project.org"); remotes::install_version("gridExtra", "2.3", repos="https://cloud.r-project.org"); remotes::install_version("ggplot2", "4.0.1", repos="https://cloud.r-project.org"); remotes::install_version("RcppParallel", "6.2.1", repos="https://cloud.r-project.org", upgrade="never"); remotes::install_version("qs2", "0.4.0", repos="https://cloud.r-project.org", upgrade="never"); remotes::install_version("ggnewscale", "0.5.2", repos="https://cloud.r-project.org", upgrade="never"); remotes::install_version("ungroup", "1.6.3", repos="https://cloud.r-project.org", upgrade="never")'

# Install Node.js 20 and Claude Code CLI
ARG CLAUDE_CODE_VERSION=latest
USER root
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} && \
    mkdir -p /home/jovyan/.claude && \
    chown jovyan:users /home/jovyan/.claude
USER jovyan
