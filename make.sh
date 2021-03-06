#!/bin/sh

IMAGE=${PODMAN_IMAGE:-mgoltzsche/podman}

set -ex

while [ $# -gt 0 ]; do
	case "$1" in
		build)
			docker build --force-rm -t ${IMAGE} .
		;;
		test)
			echo TEST PODMAN AS ROOT '(using CNI)'
			docker run --rm --privileged --entrypoint /bin/sh \
				-v "`pwd`/storage-root":/var/lib/containers/storage \
				${IMAGE} \
				-c 'podman run --cgroup-manager=cgroupfs --rm alpine:3.10 wget -O /dev/null http://example.org'
			echo TEST PODMAN AS UNPRIVILEGED USER - NETWORK '(using slirp4netns)'
			docker run -ti --rm --privileged \
				-v "`pwd`/storage-user":/podman/.local/share/containers/storage \
				${IMAGE} \
				docker run --rm alpine:3.10 wget -O /dev/null http://example.org
			echo TEST PODMAN AS UNPRIVILEGED USER - UID MAPPING '(using fuse-overlayfs)'
			docker run -ti --rm --privileged \
				-v "`pwd`/storage-user":/podman/.local/share/containers/storage \
				${IMAGE} \
				docker run --rm alpine:3.10 /bin/sh -c 'set -ex; touch /file; chown guest /file; [ $(stat -c %U /file) = guest ]'
			echo TEST BUILDAH AS UNPRIVILEGED USER
			docker run -ti --rm --privileged -u 100000:100000 --entrypoint /bin/sh \
				-v "`pwd`/storage-user":/podman/.local/share/containers/storage \
				${IMAGE} \
				-c 'set -e; CTR="$(buildah from docker.io/library/alpine:3.10)";
					buildah config --cmd "echo hello world" "$CTR";
					buildah commit "$CTR" buildahtestimage:latest'
			echo TEST PODMAN BUILD DOCKERFILE AS UNPRIVILEGED USER '(using buildah)'
			# TODO: Remove host cgroups mount workaround.
			# Required since podman 1.6 because now it seems to read
			# /proc/self/cgroup which contains the host's cgroup path
			# instead of the container-relative.
			# (Disabling cgroup management (podman run --cgroups=disabled)
			# is currently only possible when using crun instead of runc)
			docker run -ti --rm --privileged -u 100000:100000 --entrypoint /bin/sh \
				-v /sys/fs/cgroup:/sys/fs/cgroup:rw \
				-v "`pwd`/storage-user":/podman/.local/share/containers/storage \
				${IMAGE} \
				-c 'set -e;
					podman build -t podmantestimage -f - . <<-EOF
						FROM docker.io/library/alpine:3.10
						CMD ["/bin/echo", "hello world"]
					EOF'
		;;
		run)
			docker run -ti --rm --name podman --privileged \
				-v "`pwd`/storage-user":/podman/.local/share/containers/storage \
				${IMAGE} /bin/sh
		;;
	esac
	shift
done
