"""Minimal AutoLISP interpreter used ONLY to unit-test the pure sections
(1-7) of cable_tray_router.lsp without AutoCAD.

It executes the real .lsp source (not a port).  It implements the AutoLISP
semantics the router relies on: dynamic scoping of defun locals, integer vs
real arithmetic (int/int -> int), nil/T, cons cells and dotted pairs.
AutoCAD-only functions (entmake, ssget, getpoint ...) are NOT implemented and
raise LispError if a test accidentally calls them.

Limits: this proves the algorithm logic, not AutoCAD behaviour (entmake,
undo, block insertion).  Those are verified separately in AutoCAD.
"""
import math
import re
import sys


class LispError(Exception):
    pass


class Sym:
    __slots__ = ("name",)
    _tab = {}

    def __new__(cls, name):
        name = name.upper()
        s = cls._tab.get(name)
        if s is None:
            s = object.__new__(cls)
            s.name = name
            cls._tab[name] = s
        return s

    def __repr__(self):
        return self.name


class Cons:
    __slots__ = ("car", "cdr")

    def __init__(self, car, cdr):
        self.car, self.cdr = car, cdr

    def __repr__(self):
        return to_str(self)


T = Sym("T")


def from_list(items, tail=None):
    r = tail
    for x in reversed(items):
        r = Cons(x, r)
    return r


def to_list(c):
    out = []
    while isinstance(c, Cons):
        out.append(c.car)
        c = c.cdr
    return out


def to_str(x):
    if x is None:
        return "nil"
    if isinstance(x, str):
        return '"%s"' % x
    if isinstance(x, Cons):
        parts = []
        while isinstance(x, Cons):
            parts.append(to_str(x.car))
            x = x.cdr
        s = " ".join(parts)
        return "(%s%s)" % (s, "" if x is None else " . " + to_str(x))
    if isinstance(x, float):
        return repr(x)
    return str(x)


# ---------------------------------------------------------------- reader
TOKEN = re.compile(r'''\s+|;\|.*?\|;|;[^\n]*|"(?:\\.|[^"\\])*"|[()']|[^\s()';"]+''', re.S)


def tokenize(src):
    out = []
    for m in TOKEN.finditer(src):
        t = m.group(0)
        if t.isspace() or t.startswith(";"):
            continue
        out.append(t)
    return out


def parse_atom(t):
    if t.startswith('"'):
        s = t[1:-1]
        s = re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t", "e": "\x1b"}.get(m.group(1), m.group(1)), s)
        return s
    try:
        return int(t)
    except ValueError:
        pass
    try:
        return float(t)
    except ValueError:
        pass
    if t.upper() == "NIL":
        return None
    return Sym(t)


def read_all(src):
    toks = tokenize(src)
    pos = 0
    forms = []

    def rd():
        nonlocal pos
        t = toks[pos]
        pos += 1
        if t == "(":
            items, tail = [], None
            while True:
                if pos >= len(toks):
                    raise LispError("unbalanced parentheses (missing ')')")
                if toks[pos] == ")":
                    pos += 1
                    break
                if toks[pos] == ".":
                    pos += 1
                    tail = rd()
                    continue
                items.append(rd())
            return from_list(items, tail)
        if t == ")":
            raise LispError("unbalanced parentheses (extra ')')")
        if t == "'":
            return Cons(Sym("QUOTE"), Cons(rd(), None))
        return parse_atom(t)

    while pos < len(toks):
        forms.append(rd())
    return forms


# ---------------------------------------------------------------- evaluator
class Func:
    def __init__(self, name, params, locs, body):
        self.name, self.params, self.locs, self.body = name, params, locs, body


class Interp:
    def __init__(self):
        self.g = {}
        self.g["PI"] = math.pi
        self.out = []
        self.special = {
            "QUOTE": self.sf_quote, "DEFUN": self.sf_defun, "SETQ": self.sf_setq,
            "IF": self.sf_if, "COND": self.sf_cond, "WHILE": self.sf_while,
            "FOREACH": self.sf_foreach, "REPEAT": self.sf_repeat,
            "PROGN": self.sf_progn, "AND": self.sf_and, "OR": self.sf_or,
            "LAMBDA": self.sf_lambda, "FUNCTION": self.sf_quote,
        }
        self.builtins = make_builtins(self)

    # -- helpers
    def load_file(self, path):
        with open(path, encoding="utf-8") as f:
            return self.load_string(f.read())

    def load_string(self, src):
        r = None
        for form in read_all(src):
            r = self.ev(form)
        return r

    def call(self, name, *args):
        return self.apply(Sym(name), list(args))

    def ev(self, x):
        if isinstance(x, Sym):
            if x is T:
                return T
            return self.g.get(x.name)
        if not isinstance(x, Cons):
            return x
        head = x.car
        if isinstance(head, Sym):
            sf = self.special.get(head.name)
            if sf:
                return sf(x.cdr)
            args = [self.ev(a) for a in to_list(x.cdr)]
            return self.apply(head, args)
        if isinstance(head, Cons) and head.car is Sym("LAMBDA"):
            return self.apply(head, [self.ev(a) for a in to_list(x.cdr)])
        raise LispError("bad function form: %s" % to_str(x))

    def apply(self, f, args):
        if isinstance(f, Sym):
            name = f.name
            if name in self.builtins:
                return self.builtins[name](*args)
            f = self.g.get(name)
            if f is None:
                raise LispError("undefined function: %s" % name)
        if isinstance(f, Cons) and f.car is Sym("LAMBDA"):
            params, locs = self.parse_params(f.cdr.car)
            return self.invoke("lambda", params, locs, to_list(f.cdr.cdr), args)
        if isinstance(f, Func):
            return self.invoke(f.name, f.params, f.locs, f.body, args)
        raise LispError("not a function: %s" % to_str(f))

    def parse_params(self, plist):
        params, locs, inloc = [], [], False
        for p in to_list(plist):
            if p is Sym("/"):
                inloc = True
            elif inloc:
                locs.append(p.name)
            else:
                params.append(p.name)
        return params, locs

    def invoke(self, name, params, locs, body, args):
        if len(args) < len(params):
            args = args + [None] * (len(params) - len(args))
        saved = {}
        names = params + locs
        for n in names:
            saved[n] = self.g.get(n, "<unbound>")
        for n, v in zip(params, args):
            self.g[n] = v
        for n in locs:
            self.g[n] = None
        try:
            r = None
            for b in body:
                r = self.ev(b)
            return r
        finally:
            for n, v in saved.items():
                if v == "<unbound>" and isinstance(v, str):
                    self.g.pop(n, None)
                else:
                    self.g[n] = v

    # -- special forms
    def sf_quote(self, a):
        return a.car

    def sf_lambda(self, a):
        return Cons(Sym("LAMBDA"), a)

    def sf_defun(self, a):
        name = a.car.name
        params, locs = self.parse_params(a.cdr.car)
        self.g[name.upper()] = Func(name, params, locs, to_list(a.cdr.cdr))
        return Sym(name)

    def sf_setq(self, a):
        v = None
        items = to_list(a)
        for i in range(0, len(items), 2):
            v = self.ev(items[i + 1])
            self.g[items[i].name] = v
        return v

    def sf_if(self, a):
        items = to_list(a)
        if self.ev(items[0]) is not None:
            return self.ev(items[1])
        return self.ev(items[2]) if len(items) > 2 else None

    def sf_cond(self, a):
        for clause in to_list(a):
            cl = to_list(clause)
            v = self.ev(cl[0])
            if v is not None:
                r = v
                for b in cl[1:]:
                    r = self.ev(b)
                return r
        return None

    def sf_while(self, a):
        test, body = a.car, to_list(a.cdr)
        n = 0
        while self.ev(test) is not None:
            for b in body:
                self.ev(b)
            n += 1
            if n > 1_000_000:
                raise LispError("while loop exceeded 1,000,000 iterations")
        return None

    def sf_foreach(self, a):
        var = a.car.name
        lst = self.ev(a.cdr.car)
        body = to_list(a.cdr.cdr)
        saved = self.g.get(var)
        r = None
        for item in to_list(lst):
            self.g[var] = item
            for b in body:
                r = self.ev(b)
        self.g[var] = saved
        return r

    def sf_repeat(self, a):
        n = self.ev(a.car)
        r = None
        for _ in range(n):
            for b in to_list(a.cdr):
                r = self.ev(b)
        return r

    def sf_progn(self, a):
        r = None
        for b in to_list(a):
            r = self.ev(b)
        return r

    def sf_and(self, a):
        r = T
        for b in to_list(a):
            r = self.ev(b)
            if r is None:
                return None
        return r

    def sf_or(self, a):
        for b in to_list(a):
            r = self.ev(b)
            if r is not None:
                return r
        return None


def lisp_equal(a, b):
    if isinstance(a, Cons) and isinstance(b, Cons):
        return lisp_equal(a.car, b.car) and lisp_equal(a.cdr, b.cdr)
    if isinstance(a, (int, float)) and isinstance(b, (int, float)) \
            and not isinstance(a, bool) and not isinstance(b, bool):
        return a == b
    return a is b or (isinstance(a, str) and isinstance(b, str) and a == b)


def num(x):
    if isinstance(x, bool) or not isinstance(x, (int, float)):
        raise LispError("bad argument type: numberp: %s" % to_str(x))
    return x


def rtos(v, mode=2, prec=None):
    if prec is None:
        prec = 6
    s = "%.*f" % (prec, float(v))
    if mode == 2 and "." in s:
        s = s.rstrip("0").rstrip(".")
    return "-0" if s == "-0" else s


def make_builtins(it):
    b = {}

    def tb(x):
        return T if x else None

    def add(*a):
        r = 0
        for x in a:
            r += num(x)
        return r

    def sub(*a):
        if len(a) == 1:
            return -num(a[0])
        r = num(a[0])
        for x in a[1:]:
            r -= num(x)
        return r

    def mul(*a):
        r = 1
        for x in a:
            r *= num(x)
        return r

    def div(*a):
        r = num(a[0])
        for x in a[1:]:
            x = num(x)
            if x == 0:
                raise LispError("divide by zero")
            if isinstance(r, int) and isinstance(x, int):
                r = int(r / x)  # truncate toward zero like AutoLISP
            else:
                r = r / x
        return r

    def cmp_chain(op):
        def f(*a):
            for i in range(len(a) - 1):
                x, y = a[i], a[i + 1]
                if isinstance(x, str) != isinstance(y, str):
                    return None
                if not op(x, y):
                    return None
            return T
        return f

    def car(x):
        return x.car if x is not None else None

    def cdr(x):
        return x.cdr if x is not None else None

    def nth(n, l):
        items = to_list(l)
        return items[n] if 0 <= n < len(items) else None

    def append(*ls):
        items = []
        for l in ls:
            items += to_list(l)
        return from_list(items)

    def assoc(k, l):
        for e in to_list(l):
            if isinstance(e, Cons) and lisp_equal(e.car, k):
                return e
        return None

    def member(x, l):
        while isinstance(l, Cons):
            if lisp_equal(l.car, x):
                return l
            l = l.cdr
        return None

    def mapcar(f, *ls):
        lists = [to_list(l) for l in ls]
        n = min(len(l) for l in lists)
        return from_list([it.apply(f, [l[i] for l in lists]) for i in range(n)])

    def rem(a, c):
        if isinstance(a, int) and isinstance(c, int):
            return int(math.fmod(a, c))
        return math.fmod(a, c)

    def princ(*a):
        if a:
            s = a[0] if isinstance(a[0], str) else to_str(a[0])
            it.out.append(s)
            sys.stdout.write(s)
        return a[0] if a else None

    def atan(y, x=None):
        return math.atan(y) if x is None else math.atan2(y, x)

    def fix(x):
        return int(num(x))

    def minmax(fn):
        def f(*a):
            r = fn(num(x) for x in a)
            return r
        return f

    def strcat(*a):
        return "".join(a)

    def wrong(name):
        def f(*a):
            raise LispError("AutoCAD-only function called in simulator: " + name)
        return f

    b.update({
        "+": add, "-": sub, "*": mul, "/": div,
        "1+": lambda x: num(x) + 1, "1-": lambda x: num(x) - 1,
        "=": cmp_chain(lambda x, y: x == y),
        "/=": lambda x, y: tb(not (cmp_chain(lambda p, q: p == q)(x, y))),
        "<": cmp_chain(lambda x, y: x < y), ">": cmp_chain(lambda x, y: x > y),
        "<=": cmp_chain(lambda x, y: x <= y), ">=": cmp_chain(lambda x, y: x >= y),
        "EQUAL": lambda x, y, f=None: tb(lisp_equal(x, y)),
        "EQ": lambda x, y: tb(x is y or (isinstance(x, (int, float)) and x == y)),
        "NOT": lambda x: tb(x is None), "NULL": lambda x: tb(x is None),
        "CAR": car, "CDR": cdr,
        "CADR": lambda x: car(cdr(x)), "CADDR": lambda x: car(cdr(cdr(x))),
        "CDDR": lambda x: cdr(cdr(x)),
        "CONS": Cons, "LIST": lambda *a: from_list(list(a)),
        "NTH": nth, "LENGTH": lambda l: len(to_list(l)),
        "APPEND": append, "REVERSE": lambda l: from_list(list(reversed(to_list(l)))),
        "LAST": lambda l: (to_list(l) or [None])[-1],
        "ASSOC": assoc, "MEMBER": member, "MAPCAR": mapcar,
        "APPLY": lambda f, args: it.apply(f, to_list(args)),
        "ABS": lambda x: abs(num(x)), "SQRT": lambda x: math.sqrt(num(x)),
        "SIN": math.sin, "COS": math.cos, "ATAN": atan,
        "FIX": fix, "FLOAT": lambda x: float(num(x)),
        "MIN": minmax(min), "MAX": minmax(max), "REM": rem,
        "MINUSP": lambda x: tb(num(x) < 0), "ZEROP": lambda x: tb(num(x) == 0),
        "NUMBERP": lambda x: tb(isinstance(x, (int, float))),
        "LISTP": lambda x: tb(x is None or isinstance(x, Cons)),
        "ATOM": lambda x: tb(not isinstance(x, Cons)),
        "LOGAND": lambda a, c: a & c,
        "STRCAT": strcat, "ITOA": lambda x: str(int(x)), "RTOS": rtos,
        "STRCASE": lambda s, w=None: s.lower() if w else s.upper(),
        "PRINC": princ, "PRIN1": princ,
        "BOUNDP": lambda s: tb(s.name in it.g),
    })
    for n in ("ENTMAKE", "ENTGET", "ENTDEL", "SSGET", "SSLENGTH", "SSNAME",
              "TBLSEARCH", "GETPOINT", "GETREAL", "COMMAND", "GETVAR",
              "SETVAR", "REGAPP", "INITGET", "WCMATCH"):
        b[n] = wrong(n)
    return b


if __name__ == "__main__":
    it = Interp()
    for p in sys.argv[1:]:
        it.load_file(p)
