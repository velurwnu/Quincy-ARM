# Проект: Quincy 2005 для macOS 27 (Apple Silicon)

Задача: воссоздать Windows-IDE Quincy 2005 v1.3 для C/C++ **один в один** как нативное arm64-приложение для macOS 27 с максимальной оптимизацией. Оригинал — `Q2005v1_3setup.exe` в этой папке. Анализ оригинала уже сделан, повторять его не нужно.

Общайся с пользователем по-русски, кратко и по делу.

## Шаг 0. Подготовка (сделай первым)
1. Прочитай `HANDOFF.md` целиком — там все факты об оригинале и принятая архитектура.
2. Распакуй `quincy-handoff.zip` в `reference/` (и вложенный `quincy_html_help_and_bins.zip` в `reference/original/`). Это **справочные материалы, не код проекта**.
3. Внимательно изучи:
   - `reference/dumps/menu_accel_strings_toolbar.txt` — меню, акселераторы, строки статус-бара/tooltip, порядок кнопок тулбара;
   - `reference/dumps/dialogs.txt` — геометрия всех диалогов (DLU → px: x·1.5, y·1.625);
   - `reference/dumps/help_main.txt`, `help_debug_tools.txt` — поведение каждой функции;
   - `reference/dumps/quincy_exe_strings.txt` — точные тексты сообщений и флаги компилятора;
   - скриншоты оригинала: `reference/original/html/quincy2005/pics/fig*.gif` (главное окно — fig07a, fig20a; Build — fig16/fig17; Watch — fig11; Examine — fig08a; Options — fig15/15b/15c; New — fig12; Project Properties — `html/pics/ProjectProperties.gif`; Beautifier — fig31a; Replace — fig46; консоль — fig05).
4. Проверь окружение: `xcode-select -p`, `clang --version`, `lldb --version`, `lldb -b -o "script print(1)"` (нужен Python в lldb), `sw_vers`, `uname -m`. Если Command Line Tools нет — попроси пользователя выполнить `xcode-select --install`.

## Шаг 1. Каркас
- Язык: **Objective-C + AppKit, ARC**, без Swift, без сторонних фреймворков, без Electron. Сборка: `clang -arch arm64 -O2 -flto -fobjc-arc -mmacosx-version-min=13.0`, ad-hoc подпись `codesign -s -`.
- Структура: `src/*.m`, общий заголовок `src/Quincy.h`, ресурсы в `resources/`, скрипт `build.sh`, который собирает `build/Quincy 2005.app` (Info.plist, иконка .icns из кота `icon128`, увеличенного nearest-neighbor, ресурсы, HTML-справка из `reference/original/html` и `*.htm`).
- Принудительно светлая тема (`NSAppearanceNameAqua`).
- Собирай и запускай после каждого крупного этапа. Проверяй вид скриншотами (`screencapture -l <windowid>` или `screencapture -R`) и сравнивай с fig-скриншотами оригинала.

## Шаг 2. Главное окно (вид Windows 2000 внутри окна macOS)
- Системная строка меню macOS с **точно такими же** пунктами, порядком, разделителями и подменю, как в дампе. Сочетания из оригинала через ⌃ (Ctrl), F-клавиши как есть. Дополнительно стандартные ⌘C/⌘V/⌘X/⌘A/⌘Z/⇧⌘Z/⌘S/⌘O/⌘N/⌘P/⌘Q через монитор клавиатуры.
- При наведении на пункт меню показывай первую часть строки-подсказки в статус-баре (как MFC).
- Тулбар: классические серые кнопки 3D, иконки из `BITMAP_128_1033.png` (27 штук по 16 px, фон 192,192,192 → прозрачный, масштаб nearest-neighbor), разделители по дампу, tooltip — вторая часть строки. Неактивные кнопки — серые, как в Windows.
- MDI-клиент (фон 128,128,128) с дочерними окнами: градиентный заголовок (активный 10,36,106→166,202,240, неактивный серый), шрифт Tahoma bold, кнопки свернуть/развернуть/закрыть, изменение размера за рамку, перетаскивание. При развёрнутом окне заголовок приложения `Quincy 2005 - [имя]`.
- Window: New Window (второй вид того же документа через общий NSTextStorage), Cascade, Tile, Close All, Arrange Icons и список окон.
- Статус-бар: `Press F1 for help` | `Ln %d, Col %d` | CAP | NUM | SCRL.
- Сессия: восстановление открытых документов, позиций окон, Recent File List.

## Шаг 3. Редактор
- NSTextView (TextKit 1), Courier New 13pt, без переноса строк, горизонтальная прокрутка, классические (не оверлейные) скроллбары.
- Подсветка через temporary attributes с инкрементальным лексером по строкам (состояние многострочного комментария на начало строки). Цвета по умолчанию: фон белый, текст чёрный, комментарии 0,128,0, ключевые слова и `#директивы` 0,0,255, строки и символы 255,0,0.
- Tabs (stops, табы или пробелы), autoindent, Max Undos, Match braces (с учётом комментариев и строк, сообщение при отсутствии пары), Find/Replace/Find Next (диалоги как в fig45/fig46), копирование текущей строки при Copy без выделения, макросы Record/Stop/Playback.
- Левое поле: рука (`BITMAP_174`) — точка останова, зелёная стрелка (`BITMAP_172`) — текущая строка, `BITMAP_175` — оба сразу. Двойной клик по полю ставит или снимает точку останова.
- Печать / Print Setup (с флажком Print line numbers) / Print Preview через NSPrintOperation.

## Шаг 4. Диалоги
Сделай генератор вида из DLU-шаблона (данные из `dialogs.txt` перенеси в C-таблицы) на нативных контролах шрифтом 11pt. Через него построй: New (с пунктом Project и текстовыми типами), Options (вкладки Build / Run / Editor + OK / Cancel / Help; во вкладке Editor живой образец кода, выбор цветов через NSColorPanel, кнопки Restore defaults, −, +, Bold), Project Properties, Examine, Watch, Add Watch, Build, GDB Console (назови «LLDB Console»), Grep, Grep Results, Code Beautifier, Command Line, About (кот, «Quincy 2005 v1.3 05-Feb-2008», URL, логотип Dr. Dobb's, строка с версией clang и строка macOS).

## Шаг 5. Сборка программ (clang вместо MinGW)
- Флаги переносятся точно по таблице из `HANDOFF.md`: `-gstabs` заменить на `-g`, `-fshort-enums` не использовать, `-O4` превращается в `-Os`.
- Одиночный файл: Compile (F5, `-c`), Build (F6, условная сборка по mtime), Rebuild All (⌃F6), Link (⌃F5), Stop.
- Проект `.prj` (свой текстовый формат): список файлов, `.a`, свойства проекта, опции. Типы сборки: Console, Object Library (`ar rc`), DLL (`.dylib`). Win32 GUI, WinBGIm, koolplot и FLTK показывать неактивными с подсказкой «недоступно в macOS».
- Сборка асинхронная (NSTask), вывод в немодальное окно Build: командные строки, ошибки, итоговая строка `Successful build` / `Unsuccessful build` / `Build stopped by user`. Двойной клик по `file:line:` открывает файл на нужной строке.
- Тексты вопросов как в оригинале: `... is out of date. Rebuild?`, `No debug information. Run anyway?`, `Terminate running program?`.

## Шаг 6. Запуск и консоль
- Собственное окно консоли: чёрный фон, серый 192,192,192 текст, моноширинный шрифт, 80×25, заголовок «Quincy 2005», позиция запоминается.
- Работает через pty: `openpty` + `fork`, в дочернем процессе `setsid`, `ioctl TIOCSCTTY`, `dup2`, `chdir`, `execve`. Нужна мини-эмуляция терминала (`\r \n \b \t`, игнорировать ESC-последовательности); Ctrl+C отправляет 0x03.
- После завершения программы выводится `Press Enter to return to Quincy...`, по Enter окно закрывается.
- Параметры из вкладки Run: аргументы (нет / спрашивать каждый раз / фиксированные) и рабочая папка.

## Шаг 7. Отладчик (lldb)
- Протокол уже проверен, он описан в `HANDOFF.md`: `lldb --no-lldbinit` через pipes, `SetAsync(False)`, свои frame-format и thread-stop-format, маркер `script print("@@DONE<n>")` после каждой команды.
- Ввод-вывод программы идёт через pty консоли: `process launch -i/-o/-e <slave>`.
- Команды: Run/Continue (F9; при наличии точек останова запуск под отладчиком), Step (F7) = `step`, Step Over (F8) = `next`, Step To Cursor (F10) = `tbreak` + `continue`, Step Out = `finish`, Stop = kill инферьора и `quit`.
- Если программа остановилась в файле, которого нет на диске, автоматически делай `finish`.
- Точки останова, поставленные во время работы программы, ставь в очередь и применяй при следующей остановке.
- Watch обновляется при каждой остановке в формате `expr := value`, ошибка вычисления показывается как `??`. Examine показывает значение, Change выполняет `expression -- expr = value`.
- LLDB Console показывает весь диалог с lldb.
- Если macOS не даёт отлаживать, сообщи пользователю про `sudo DevToolsSecurity -enable`.

## Шаг 8. Инструменты и справка
- Grep: нативный поиск по файлам `*.c *.cpp *.cc *.cxx *.h *.rc` в папке документа или проекта, опции Match case и Match word, двойной клик открывает файл на строке, Stop прерывает поиск.
- Code Beautifier: AStyle 2.06 (`git clone https://github.com/steinwurf/astyle`) вкомпилировать как библиотеку (`-DASTYLE_LIB`, `AStyleMain`). Пресеты K&R / ANSI / GNU / ALLMAN-BSD / Custom с теми же командными строками, что в оригинале, плюс Test и живой образец.
- Command Prompt: открыть Terminal в папке проекта. Resource Editor и FLUID — неактивны.
- Help: User's Guide открывает `quincy2005.htm`, Programmer's Help — `programmerGuide.htm`, F4 / Example Programs — `tutorial.htm`. Всё из бандла, в браузере по умолчанию.

## Шаг 9. Проверка (обязательно перед сдачей)
1. Создать C++-файл Hello World → F6 → F9: в консоли вывод и `Press Enter...`.
2. Программа с ошибкой: двойной клик по ошибке переходит на строку.
3. Отладка: F2 на строке → F9 (остановка) → F7/F8/Step Out → Watch с выражением → Examine/Change → Stop.
4. Проект из двух `.cpp` и одного `.h` → Build → Run; библиотека `.a` и `.dylib`.
5. Grep, Beautifier, Find/Replace, Match braces, макросы, Undo/Redo, печать в PDF.
6. Перезапуск: сессия восстанавливается.
7. Сравнить скриншоты с оригиналом и устранить расхождения.
8. Замерить скорость запуска и потребление памяти, проверить отсутствие утечек (`leaks`).

В конце: `build/Quincy 2005.app` лежит в этой папке, плюс короткий `README.md` (как собрать, что отличается от Windows-оригинала и почему).
