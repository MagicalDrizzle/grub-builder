# podman build --secret=id=db.key --secret=id=db.pem --output type=local,dest=output -t grub-builder .
# optional: --build-arg PREFIX=abc --secret id=sbat,src=sbat.csv
FROM quay.io/fedora/fedora-minimal:latest AS builder
WORKDIR /build
ARG PREFIX=
# list taken from grubs.macro in fedora's source repo'
ENV MODULES="\
    all_video boot blscfg btrfs blsuki cat configfile cryptodisk \
    echo exfat ext2 f2fs fat font \
    gcry_rijndael gcry_rsa gcry_serpent \
    gcry_sha256 gcry_twofish gcry_whirlpool \
    gfxmenu gfxterm gzio halt hfsplus http increment iso9660 \
    jpeg loadenv loopback linux lvm luks luks2 memdisk \
    mdraid09 mdraid1x minicmd net \
    normal part_apple part_msdos part_gpt \
    password_pbkdf2 pgp png reboot regexp \
    search search_fs_uuid search_fs_file \
    search_label serial sleep squash4 syslinuxcfg \
    test tftp version video xfs zstd \
    \
    efi_netfs efifwsetup efinet lsefi lsefimmap connectefi bli \
    \
    backtrace chain tpm usb usbserial_common usbserial_pl2303 \
    usbserial_ftdi usbserial_usbdebug keylayouts at_keyboard \
"
RUN --mount=type=secret,id=sbat,target=/run/secrets/sbat.csv,required=false \
    set -euo pipefail; rm -rf /build/*; \
    dnf install -y --setopt=install_weak_deps=False binutils \
        sbsigntools grub2-tools grub2-efi-x64-modules shim-x64 && dnf clean all; \
    cp /usr/lib/efi/grub2/*/EFI/fedora/grubx64.efi \
       /usr/lib/efi/shim/*/EFI/fedora/shimx64.efi \
       /usr/lib/efi/shim/*/EFI/fedora/mmx64.efi \
       -t .; \
    printf '%s\n' 'configfile ${cmdpath}/grub.cfg' > embedded.cfg; \
    objcopy --dump-section .sbat=sbat-rh.csv grubx64.efi /tmp/dummy && rm -f /tmp/dummy; \
    sbat_file="sbat-rh.csv"; \
    if [ -f /run/secrets/sbat.csv ]; then \
        sbat_file="/run/secrets/sbat.csv"; \
    fi; \
    if [ -n "$PREFIX" ]; then \
        NAME=$(printf '%s' "$PREFIX" | sed 's#^/##; s#/#-#g'); \
        grub2-mkimage -C xz -O x86_64-efi -d /usr/lib/grub/x86_64-efi -s "$sbat_file" \
        -p "$PREFIX" \
        -o "grubx64_${NAME}.efi" \
        $MODULES; \
    else \
        grub2-mkimage -C xz -O x86_64-efi -d /usr/lib/grub/x86_64-efi \
        -p /EFI/grub-portable -c embedded.cfg --disable-shim-lock \
        -o grubx64_portable_standalone.efi \
        $MODULES; \
        grub2-mkimage -C xz -O x86_64-efi -d /usr/lib/grub/x86_64-efi -s "$sbat_file" \
        -p /EFI/Linux/aurora \
        -o grubx64_aurora.efi \
        $MODULES; \
        grub2-mkimage -C xz -O x86_64-efi -d /usr/lib/grub/x86_64-efi -s "$sbat_file" \
        -p /EFI/Linux/ultramarine \
        -o grubx64_ultramarine.efi \
        $MODULES; \
        grub2-mkimage -C xz -O x86_64-efi -d /usr/lib/grub/x86_64-efi -s "$sbat_file" \
        -p /EFI/Linux/blossomos \
        -o grubx64_blossomos.efi \
        $MODULES; \
    fi

RUN --mount=type=secret,id=db.key --mount=type=secret,id=db.pem \
    set -euo pipefail; \
    for f in grubx64_*.efi; do \
        sbsign --key /run/secrets/db.key --cert /run/secrets/db.pem "$f"; \
    done
FROM scratch AS exporter
COPY --from=builder /build/shimx64.efi /build/mmx64.efi /build/grubx64*.efi* /
