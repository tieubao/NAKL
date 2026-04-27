Monke - Vietnamese input keyboard for macOS
=======

A modernised redistribution of [NAKL](https://github.com/huyphan/NAKL)
(Huy Phan, 2012). Bundle identifier `foundation.d.Monke`. Builds on
macOS 14+, signed and notarisable for Developer ID distribution.

The Vietnamese transformation engine, Telex / VNI rules, and the keymap
are inherited verbatim from [xvnkb](http://xvnkb.sourceforge.net/) (Dao
Hai Lam) via NAKL. The shell around it has been rewritten incrementally
through the SPEC-driven track in [`specs/`](specs/).

Building
=======

```bash
xcodebuild -project NAKL.xcodeproj -scheme NAKL -configuration Debug
```

Output: `build/Debug/Monke.app`. The app needs Accessibility permission
on first launch to install its global event tap; macOS will prompt you.

Contributing
=======

* Issues and patches via this repository.
* No code lands without an approved spec. See
  [`specs/README.md`](specs/README.md) for the workflow. Architecture
  decisions live in [`adr/`](adr/).

Credits
=======

* **Dao Hai Lam** (chuoi) — author of [xvnkb](http://xvnkb.sourceforge.net/),
  the source of the keymap and the Telex/VNI key-handling algorithm.
* **Huy Phan** (dachuy) — author of NAKL (2012), the upstream this
  redistribution forks and modernises. Original homepage:
  http://huyphan.github.com/NAKL.
* **mybb** (hieuln) and **pmquan** (co\`i) — testers of the original NAKL.

License
=======

* Distributed under the **GNU GPLv3**. See [LICENSE](LICENSE).
  Redistribution under this license is the explicit purpose of this
  fork; you may further modify and re-bundle as long as the licence
  stays GPLv3 and the credits above are preserved.
* HotKey setting is based on
  [ShortcutRecorder](http://wafflesoftware.net/shortcut/).
