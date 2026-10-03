"""Single place that decides where the regression tools look for the BLOCK / router folders.

    CTR_BLOCK_DIR         root of the BLOCK folder        (default D:\\BLOCK)
    CTR_BLOCK_ROUTER_DIR  the router folder inside it     (default <CTR_BLOCK_DIR>/router, i.e. D:\\BLOCK\\router)

With neither variable set the behaviour is exactly the historical one (production D:\\BLOCK).
tools/run_isolated_regression.py sets both to a scratch folder so nothing under D:\\BLOCK is written.
Note: the router core itself still READS fitting .dwg files from D:/BLOCK/ (*CTR-BLOCK-DIRS*); that is read only.
"""
from __future__ import annotations

import os
from pathlib import Path

DEFAULT_BLOCK_DIR = r"D:\BLOCK"


def get_block_dir() -> Path:
    v = os.environ.get("CTR_BLOCK_DIR")
    return Path(os.path.abspath(v)) if v else Path(DEFAULT_BLOCK_DIR)


def get_block_router_dir() -> Path:
    v = os.environ.get("CTR_BLOCK_ROUTER_DIR")
    return Path(os.path.abspath(v)) if v else get_block_dir() / "router"


def lisp_path(p) -> str:
    """Forward-slash form, as written into LISP source / loader text."""
    return str(p).replace("\\", "/")


def rp(rel: str) -> str:
    """Path of <router dir>/<rel> in LISP (forward-slash) form; default: D:/BLOCK/router/<rel>."""
    return lisp_path(get_block_router_dir()) + "/" + rel
