#!/usr/bin/env python3
"""Build unmodified independent peers at exact revisions, outside the source tree."""
import argparse
from pathlib import Path
import subprocess

# Agent/client releases v3.0.1; dependency revisions used by the validated build.
REVISIONS = {
    "Micro-CDR": "99672492c5ef9fc378a8835b0bce9b2f7fa41306",
    "Micro-XRCE-DDS-Client": "bdfa28090efc8c0e89aa5c95cdf0878c8289a18b",
    "Fast-CDR": "757d5e422253568c487ad97c22e44680fc1ddbaf",
    "Fast-DDS": "51521ef94b859757e951b1b05317603a36c64b6e",
    "spdlog": "eb3220622e73a4889eee355ffa37972b3cac3df5",
    "Micro-XRCE-DDS-Agent": "155cfaaf8b7abac2e85d4a62d3649b09ace0be55",
}


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def build(work, name, jobs, *options):
    source = work / "src" / name
    if not source.exists():
        source.mkdir(parents=True)
        run("git", "-C", source, "init")
        owner = "gabime" if name == "spdlog" else "eProsima"
        run("git", "-C", source, "remote", "add", "origin", f"https://github.com/{owner}/{name}.git")
    run("git", "-C", source, "fetch", "--depth=1", "origin", REVISIONS[name])
    run("git", "-C", source, "checkout", "--detach", REVISIONS[name])
    if name == "Fast-DDS":
        run("git", "-C", source, "submodule", "update", "--init", "--recursive", "--depth=1")
    prefix = work / "install"
    binary = work / "build" / name
    run("cmake", "-S", source, "-B", binary, "-DCMAKE_BUILD_TYPE=Release",
        f"-DCMAKE_INSTALL_PREFIX={prefix}", f"-DCMAKE_PREFIX_PATH={prefix}",
        f"-DCMAKE_INSTALL_RPATH={prefix / 'lib'}", "-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON",
        "-DCMAKE_INSTALL_LIBDIR=lib", *options)
    run("cmake", "--build", binary, "--parallel", jobs)
    run("cmake", "--install", binary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", required=True, type=Path)
    parser.add_argument("--agent", action="store_true", help="Also build the Fast DDS-backed agent")
    parser.add_argument("--jobs", default="2")
    args = parser.parse_args()
    work = args.work.resolve()
    build(work, "Micro-CDR", args.jobs, "-DBUILD_SHARED_LIBS=OFF",
          "-DUCDR_SUPERBUILD=OFF", "-DUCDR_ISOLATED_INSTALL=OFF")
    build(work, "Micro-XRCE-DDS-Client", args.jobs, "-DUCLIENT_SUPERBUILD=OFF",
          "-DUCLIENT_PROFILE_SHARED_MEMORY=OFF", "-DUCLIENT_PROFILE_DISCOVERY=OFF",
          "-DUCLIENT_BUILD_EXAMPLES=OFF", "-DBUILD_SHARED_LIBS=OFF")
    if args.agent:
        build(work, "Fast-CDR", args.jobs)
        build(work, "Fast-DDS", args.jobs, "-DTHIRDPARTY=ON", "-DCOMPILE_TOOLS=OFF",
              "-DSECURITY=OFF", "-DSHM_TRANSPORT_DEFAULT=OFF")
        build(work, "spdlog", args.jobs, "-DSPDLOG_BUILD_SHARED=OFF", "-DCMAKE_POSITION_INDEPENDENT_CODE=ON")
        build(work, "Micro-XRCE-DDS-Agent", args.jobs, "-DUAGENT_SUPERBUILD=OFF",
              "-DUAGENT_USE_SYSTEM_FASTCDR=ON", "-DUAGENT_USE_SYSTEM_FASTDDS=ON",
              "-DUAGENT_USE_SYSTEM_LOGGER=ON", "-DUAGENT_CED_PROFILE=OFF",
              "-DUAGENT_P2P_PROFILE=OFF", "-DUAGENT_SOCKETCAN_PROFILE=OFF")
    print(f"Independent peers installed in {work / 'install'}", flush=True)


if __name__ == "__main__":
    main()
