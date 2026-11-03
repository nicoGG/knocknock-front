#!/usr/bin/env python3
"""Complete an APK release without replacing assets or reusing another commit's tag."""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


class ReleaseError(RuntimeError):
    pass


def sha256_file(filename):
    digest = hashlib.sha256()
    with open(filename, "rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class GitHub:
    def __init__(self, repository):
        self.repository = repository

    def get(self, endpoint, *, missing_ok=False):
        result = subprocess.run(
            ["gh", "api", "--include", "--method", "GET",
             f"repos/{self.repository}/{endpoint}"],
            capture_output=True, text=True, check=False,
        )
        headers, _, body = result.stdout.partition("\n\n")
        status = re.match(r"HTTP/\S+ (\d{3})", headers)
        if missing_ok and status and status[1] == "404":
            return None
        if result.returncode or not status or status[1] != "200":
            raise ReleaseError(f"No se pudo consultar GitHub ({endpoint}). {result.stderr.strip()}")
        return json.loads(body)

    def command(self, *args):
        subprocess.run(["gh", "release", *args, "--repo", self.repository], check=True)


class Release:
    def __init__(self, github, source_sha, version):
        if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
            raise ReleaseError("El commit del codigo debe ser un SHA completo.")
        if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+\+[1-9][0-9]*", version):
            raise ReleaseError(f"Version no valida: {version}")
        self.github = github
        self.source_sha = source_sha
        self.build_name, self.build_number = version.split("+")
        self.tag = f"v{self.build_name}-build-{self.build_number}"
        self.apk = f"NockNock-{self.build_name}-build-{self.build_number}-release.apk"
        self.names = (self.apk, f"{self.apk}.sha256")

    def inspect(self):
        release = self.github.get(f"releases/tags/{self.tag}", missing_ok=True)
        ref = self.github.get(f"git/ref/tags/{self.tag}", missing_ok=True)
        target = ref["object"] if ref else None
        # Annotated tags can point to another tag; always compare the final commit.
        for _ in range(10):
            if not target or target["type"] != "tag":
                break
            target = self.github.get(f"git/tags/{target['sha']}")["object"]
        if target and (target["type"] != "commit" or target["sha"] != self.source_sha):
            raise ReleaseError(
                f"El tag {self.tag} no apunta al commit {self.source_sha}. "
                "Incrementa la version para publicar codigo diferente."
            )
        if release and not target:
            raise ReleaseError(f"La release {self.tag} no tiene un tag verificable.")
        if release and release.get("draft"):
            raise ReleaseError(f"La release {self.tag} es un borrador; revisala antes de continuar.")
        assets = {}
        if release:
            page = 1
            while True:
                batch = self.github.get(f"releases/{release['id']}/assets?per_page=100&page={page}")
                for asset in batch:
                    if asset["name"] in assets:
                        raise ReleaseError(f"Asset duplicado: {asset['name']}")
                    assets[asset["name"]] = asset
                if len(batch) < 100:
                    break
                page += 1
        return release, assets

    def needs_build(self):
        _, assets = self.inspect()
        return not all(name in assets for name in self.names)

    def publish(self):
        for name in self.names:
            if not Path(name).is_file():
                raise ReleaseError(f"Falta el archivo {name}.")
        digest = sha256_file(self.apk)
        if Path(self.names[1]).read_text().strip() != f"{digest}  {self.apk}":
            raise ReleaseError("El checksum local no corresponde al APK.")

        release, assets = self.inspect()
        if not release:
            try:
                self.github.command(
                    "create", self.tag, "--target", self.source_sha,
                    "--title", f"NockNock {self.build_name} ({self.build_number})",
                    "--generate-notes",
                )
            except subprocess.CalledProcessError:
                # Another publisher may have created it after the preflight.
                release, _ = self.inspect()
                if not release:
                    raise
            release, assets = self.inspect()
            if not release:
                raise ReleaseError("GitHub no devolvio la release creada.")

        missing = [name for name in self.names if name not in assets]
        if not missing:
            print(f"{self.tag} ya contiene el APK y su checksum; se conservan.")
            return

        # A retry after a partial upload must not mix a new APK with an old checksum.
        with tempfile.TemporaryDirectory(prefix="nocknock-release-") as directory:
            for name in self.names:
                if name not in assets:
                    continue
                self.github.command("download", self.tag, "--pattern", name, "--dir", directory)
                if sha256_file(Path(directory, name)) != sha256_file(name):
                    raise ReleaseError(f"El asset existente {name} difiere del archivo local; no se sobrescribe.")

        # No --clobber: concurrent uploads or existing AABs must never be replaced.
        self.github.command("upload", self.tag, *missing)
        _, assets = self.inspect()
        if not all(name in assets for name in self.names):
            raise ReleaseError("La carga no dejo ambos archivos disponibles en GitHub.")
        print(f"APK y checksum disponibles en {self.tag}.")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("check", "publish"):
        raise ReleaseError("Uso: github_release.py check|publish")
    version_lines = re.findall(r"^version:\s*(\S+)\s*$", Path("pubspec.yaml").read_text(), re.MULTILINE)
    if len(version_lines) != 1:
        raise ReleaseError("pubspec.yaml debe declarar una version unica.")
    source_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    release = Release(GitHub(os.environ["GITHUB_REPOSITORY"]), source_sha, version_lines[0])
    if sys.argv[1] == "publish":
        release.publish()
        return
    needs_build = release.needs_build()
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"needs_build={str(needs_build).lower()}\n")
    with open(os.environ["GITHUB_ENV"], "a") as output:
        output.write(f"BUILD_NAME={release.build_name}\nBUILD_NUMBER={release.build_number}\n")
        output.write(f"RELEASE_TAG={release.tag}\nAPK_NAME={release.apk}\nSOURCE_SHA={source_sha}\n")
    print(f"{release.tag}: commit {source_sha}; generar APK={needs_build}.")


if __name__ == "__main__":
    try:
        main()
    except (ReleaseError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
