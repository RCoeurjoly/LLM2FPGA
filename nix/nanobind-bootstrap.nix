{ stdenv, fetchFromGitHub, python, }:

let version = "2.10.2";
in stdenv.mkDerivation {
  pname = "nanobind-bootstrap";
  inherit version;

  src = fetchFromGitHub {
    owner = "wjakob";
    repo = "nanobind";
    rev = "v${version}";
    fetchSubmodules = true;
    hash = "sha256-io44YhN+VpfHFWyvvLWSanRgbzA0whK8WlDNRi3hahU=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    pkg="$out/${python.sitePackages}/nanobind"
    mkdir -p "$pkg"
    cp -r cmake ext include src "$pkg/"
    cp src/__init__.py src/__main__.py src/stubgen.py "$pkg/"

    printf '%s\n' \
      'set(PACKAGE_VERSION "2.10.2")' \
      'if(PACKAGE_VERSION VERSION_LESS PACKAGE_FIND_VERSION)' \
      '  set(PACKAGE_VERSION_COMPATIBLE FALSE)' \
      'else()' \
      '  set(PACKAGE_VERSION_COMPATIBLE TRUE)' \
      '  if(PACKAGE_FIND_VERSION STREQUAL PACKAGE_VERSION)' \
      '    set(PACKAGE_VERSION_EXACT TRUE)' \
      '  endif()' \
      'endif()' \
      > "$pkg/cmake/nanobind-config-version.cmake"

    runHook postInstall
  '';
}
