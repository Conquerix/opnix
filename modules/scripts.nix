{ config, options, lib, ... }:
let
  cfg = config.opnix;
  op = cfg.opBin;
  isDarwin =
    lib.attrsets.hasAttrByPath [ "environment" "darwinConfig" ] options;
  mountCommand = if isDarwin then ''
    if ! diskutil info "${cfg.secretsMountPoint}" &> /dev/null; then
        num_sectors=1048576
        dev=$(hdiutil attach -nomount ram://"$num_sectors" | sed 's/[[:space:]]*$//')
        newfs_hfs -v opnix "$dev"
        mount -t hfs -o nobrowse,nodev,nosuid,-m=0751 "$dev" "${cfg.secretsMountPoint}"
    fi
  '' else ''
    grep -q "${cfg.secretsMountPoint} ramfs" /proc/mounts ||
      mount -t ramfs none "${cfg.secretsMountPoint}" -o nodev,nosuid,mode=0751
  '';
  newGeneration = ''
    _opnix_generation="$(basename "$(readlink ${cfg.secretsDir})" || echo 0)"
    (( ++_opnix_generation ))
    echo "[opnix] creating new generation in ${cfg.secretsMountPoint}/$_opnix_generation"
    mkdir -p "${cfg.secretsMountPoint}"
    chmod 0751 "${cfg.secretsMountPoint}"
    ${mountCommand}
    mkdir -p "${cfg.secretsMountPoint}/$_opnix_generation"
    chmod 0751 "${cfg.secretsMountPoint}/$_opnix_generation"
  '';
  chownGroup = if isDarwin then "admin" else "keys";
  # chown the secrets mountpoint and the current generation to the keys group
  # instead of leaving it root:root.
  chownMountPoint = ''
    chown :${chownGroup} "${cfg.secretsMountPoint}" "${cfg.secretsMountPoint}/$_opnix_generation"
  '';
  cleanupAndLink = ''
    _opnix_generation="$(basename "$(readlink ${cfg.secretsDir})" || echo 0)"
    (( ++_opnix_generation ))
    echo "[opnix] symlinking new secrets to ${cfg.secretsDir} (generation $_opnix_generation)..."
    ln -sfT "${cfg.secretsMountPoint}/$_opnix_generation" ${cfg.secretsDir}

    (( _opnix_generation > 1 )) && {
    echo "[opnix] removing old secrets (generation $(( _opnix_generation - 1 )))..."
    rm -rf "${cfg.secretsMountPoint}/$(( _opnix_generation - 1 ))"
    }
  '';
  setTruePath = secretType: ''
    ${if secretType.symlink then ''
      _truePath="${cfg.secretsMountPoint}/$_opnix_generation/${secretType.name}"
    '' else ''
      _truePath="${secretType.path}"
    ''}
  '';
  chownSecret = secretType: ''
    ${setTruePath secretType}
    chown ${secretType.owner}:${secretType.group} "$_truePath"
  '';
  chownSecrets = builtins.concatStringsSep "\n"
    ([ "echo '[opnix] chowning...'" ] ++ [ chownMountPoint ]
      ++ (map chownSecret (builtins.attrValues cfg.secrets)));
  # TODO
  installSecret = secretType: ''
    ${setTruePath secretType}
    echo "decrypting '${secretType.file}' to '$_truePath'..."
    TMP_FILE="$_truePath.tmp"

    mkdir -p "$(dirname "$_truePath")"
    [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && mkdir -p "$(dirname "${secretType.path}")"
    (
      umask u=r,g=,o=
      test -f "${secretType.file}" || echo '[opnix] WARNING: encrypted file ${secretType.file} does not exist!'
      test -d "$(dirname "$TMP_FILE")" || echo "[opnix] WARNING: $(dirname "$TMP_FILE") does not exist!"
      echo ${secretType.source} | OP_SERVICE_ACCOUNT_TOKEN=$(cat ${cfg.serviceAccountTokenPath}) ${op} inject -o "$TMP_FILE"
    )
    chmod ${secretType.mode} "$TMP_FILE"
    mv -f "$TMP_FILE" "$_truePath"

    ${lib.optionalString secretType.symlink ''
      [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && ln -sfT "${cfg.secretsDir}/${secretType.name}" "${secretType.path}"
    ''}
  '';
  # TODO check that:
  # - config.serviceAccountTokenPath exists
  # - it is not world-readable
  # - it is readable by the user that runs `activationScript`s (need to figure out what this user is)
  testServiceAccountToken = "";
  installSecrets = builtins.concatStringsSep "\n"
    ([ "echo '[opnix] decrypting secrets...'" ] ++ testServiceAccountToken
      ++ (map installSecret (builtins.attrValues cfg.secrets))
      ++ [ cleanupAndLink ]);
in {
  inherit newGeneration;
  inherit installSecrets;
  inherit chownSecrets;
}
