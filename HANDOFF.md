# Quincy 2005 → macOS 27 arm64: передача работы

Цель: воссоздать Quincy 2005 v1.3 (Al Stevens / codecutter, MFC MDI IDE для C/C++) один в один как нативное arm64-приложение для macOS 27 с максимальной оптимизацией.

## Статус
- ✅ Установщик `Q2005v1_3setup.exe` распакован (innoextract). Из `bin/quincy.exe` извлечены ВСЕ ресурсы (pefile).
- ✅ Изучены встроенная справка и скриншоты оригинала.
- ✅ Проверено: отладчик lldb через каналы в синхронном режиме работает (см. ниже).
- ⛔ Код приложения ещё НЕ начат.

## Что в архиве `quincy-handoff.zip`
- `dumps/menu_accel_strings_toolbar.txt` — полное меню, 3 таблицы акселераторов, все строки (подсказки статус-бара + tooltip после `\n`), порядок кнопок тулбара.
- `dumps/dialogs.txt` — все 18 диалогов: контролы, id, координаты в DLU (MS Sans Serif 8: x·1.5, y·1.625 → px).
- `dumps/quincy_exe_strings.txt` — все строки exe (флаги gcc, команды gdb, сообщения, ключи настроек).
- `dumps/help_main.txt`, `help_debug_tools.txt` — текст руководства пользователя (поведение всех функций).
- `res_png/` — тулбар `BITMAP_128` (27 иконок 16×16, фон RGB 192,192,192 = прозрачный), `BITMAP_137` (логотип Dr. Dobb's для About), `BITMAP_172` стрелка, `174` рука-брейкпойнт, `175` рука+стрелка, иконки: `icon128` кот (иконка приложения), `icon129` «Qnc» (проект), 151–159 книжки/страница (дерево примеров).
- `quincy_html_help_and_bins.zip` — оригинальные `html/` (справка, tutorials, programmerHelp 24 МБ), `bin/`, `include/`, `lib/`.
- `scripts/` — парсеры ресурсов (dumpres.py, parse.py, dlg.py).

## Ключевые факты об оригинале
**Меню** (`&File/Edit/View/Project/Debug/Tools/Window/Help`), горячие клавиши: New Ctrl+N, Open Ctrl+O, Save Ctrl+S, Print Ctrl+P, Undo Ctrl+Z/Alt+Back, Redo Ctrl+Y, Find Ctrl+F, Replace Ctrl+H, Find Next F3, Match braces Ctrl+{, Watch Window Ctrl+W, Insert File(s) Ins, Delete File(s) Del, Compile F5, Link Ctrl+F5, Build F6, Rebuild All Ctrl+F6, Run/Execute F9, Step F7, Step Over F8, Step To Cursor F10, Breakpoint F2, Examine Ctrl+E, Macro Record Alt+R / Stop Alt+S / Playback Alt+M, Example Programs F4, Help F1.

**Тулбар**: New Open Save SaveAll | Print Preview | Cut Copy Paste Find | Undo Redo | MatchBraces | Build RebuildAll | Stop Run Step StepOver StepToCursor StepOut | Breakpoint ClearBreakpoints | Watch Examine | Examples Tutorial.

**Флаги компилятора** (Options → Build): debug `-gstabs`(→ `-g`), без RTTI `-fno-rtti`, без исключений `-fno-exceptions`, `-O<n>` (4 = for space → `-Os`), Strict `-pedantic-errors -Wno-long-long` + `-std=c++98` / `-std=iso9899:199409`, C99 `-std=c99 -fgnu89-inline`, Warnings All `-Wall -Wextra -Wconversion -Wshadow -Wpointer-arith -Wcast-qual -Wcast-align -Wwrite-strings -fno-common`, None `-w`, Defines `;`-разделённые → `-D`, Includes `-I`, Libraries `-L`, + Compiler options / Linker options. Библиотека: `ar rc`; DLL → `.dylib` (`-dynamiclib`).
Сообщения: `Successful build`, `Unsuccessful build`, `Build stopped by user`, `Checking dependencies`, `X is up to date`, `X is out of date. Rebuild?`, `No debug information. Run anyway?`, `Terminate running program?`, `Press Enter to return to Quincy...`.

**Цвета подсветки по умолчанию**: фон белый, текст чёрный, комментарии зелёные (0,128,0), ключевые слова и `#директивы` синие (0,0,255), строки красные (255,0,0). Шрифт Courier New 10pt. Tabs 4, Max Undos 1024, Autoindent вкл.

**Watch**: строки вида `celsius := 82`, недоступно → `??`. **Examine**: Expression / Value / Change, OK / Close.
**Build** — немодальный диалог со списком команд и ошибок; двойной клик по ошибке → строка в редакторе.
**Code Beautifier** (AStyle): K&R `--mode=c --indent-switches --brackets=linux`, ANSI `--style=ansi`, GNU `--style=gnu --indent-blocks`, ALLMAN/BSD (по умолчанию в 1.3) `--break-blocks --brackets=break --indent-namespaces --pad=oper`, + `--indent=tab|spaces=N` из настроек редактора.
**Сессия**: при запуске открываются документы прошлой сессии (ключи `Document%d`, `Document%d Maximized`, `WindowPos`, `Console Position`, Recent File List).

## Принятые решения по архитектуре (план)
- Objective-C + AppKit, ARC, `-O2`, один бинарь arm64, без Swift/Electron. Зависимость в рантайме — Xcode Command Line Tools (clang, lldb), как оригинал зависел от MinGW.
- Классический вид Win2000 внутри окна: серый тулбар с оригинальными битмапами (nearest-neighbor), MDI-клиент (серый 128,128,128) с дочерними окнами (градиентный синий заголовок, кнопки свернуть/развернуть/закрыть), статус-бар `Press F1 for help` | `Ln %d, Col %d`. Строка меню — системная macOS, сочетания как в оригинале (⌃ вместо Ctrl) + стандартные ⌘-сочетания дополнительно. Тема принудительно светлая.
- Диалоги — генератор из DLU-шаблонов (точная геометрия оригинала) на нативных контролах.
- Редактор: NSTextView (TextKit 1), подсветка через temporary attributes с инкрементальным лексером по строкам, поле слева для руки-брейкпойнта и зелёной стрелки (двойной клик = брейкпойнт).
- Консоль: собственное окно (чёрный фон, серый текст, 80×25) на pty (`openpty` + fork/`setsid`/`TIOCSCTTY`/exec), после выхода — `Press Enter to return to Quincy...`.
- Отладчик: `lldb --no-lldbinit` через pipes. Проверенная последовательность:
  ```
  script lldb.debugger.SetAsync(False)
  settings set use-color false
  settings set stop-line-count-before 0
  settings set stop-line-count-after 0
  settings set stop-disassembly-display never
  settings set frame-format "@@F ${line.file.fullpath}:${line.number}:${function.name}\n"
  settings set thread-stop-format "@@S ${thread.stop-reason}\n"
  target create <exe>
  breakpoint set -f <file> -l <line>
  process launch -i <pty-slave> -o <pty-slave> -e <pty-slave> -w <dir> -- <args>
  ```
  После каждой команды слать `script print("@@DONE<n>")` и читать до маркера. Step=`step`, Step Over=`next`, Step Out=`finish`, Step To Cursor=`tbreak`+`continue`, Examine=`expression -- <expr>` (ответ `(type) $N = value`, `error:` → `??`), выход: `Process N exited with status = X`. Stop = kill pid инферьора. На Mac может понадобиться `sudo DevToolsSecurity -enable`.
- AStyle 2.06 (github.com/steinwurf/astyle) вкомпилировать как библиотеку (`-DASTYLE_LIB`, `AStyleMain`) — без внешнего процесса.
- Недоступно на macOS (показать неактивными): Win32 GUI / WinBGIm / koolplot / FLTK типы проектов, Resource Editor, FLUID. Command Prompt → Terminal в папке проекта. Справка — оригинальные HTML в браузере.
- Иконка .app — кот `icon128`, масштаб nearest-neighbor, `.icns` из PNG.
