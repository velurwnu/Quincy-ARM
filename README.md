<div align="center">

<img src="resources/icon-128.png" width="128" alt="Quincy 2005 Icon">

# Quincy 2005 for macOS (Apple Silicon)

**English** | [Русский](#quincy-2005-для-macos-apple-silicon-ru)

</div>

---

## Quincy 2005 for macOS (Apple Silicon)

A native reimplementation of the classic **Quincy 2005 v1.3** C/C++ IDE (originally created by Al Stevens for Windows). Re-architected in native **Objective-C + AppKit** for Apple Silicon (`arm64`).

Designed to feel right at home on modern macOS with a native sidebar, document tabs, unified system toolbar, integrated build output & console panel, Watch inspector, and Settings window — while keeping all original commands, menus, shortcuts, and core workflows intact.

---

### Features

- **Native Compiler & Toolchain:** Uses Apple Clang instead of MinGW, with automatic header dependency tracking (`-MMD`).
- **Interactive Debugger:** Full LLDB integration replacing GDB. Set breakpoints by clicking line numbers or pressing **F2**, inspect variables with Watch (**⌥⌘0**), examine memory (**⌃⌘E**), and issue direct LLDB commands in the Console tab.
- **Dedicated Console Execution:** Programs run in their own interactive console window, displaying `Press Enter to return to Quincy...` upon completion.
- **Multiple Windows & Tabs:** Tabs for open files, plus **Window ▸ New Window** to view the same document simultaneously (sharing text storage, undo stack, and breakpoints).
- **Macro Recorder:** Record and play back keystrokes in the editor (including arrow keys and Enter); replay can be undone with a single **⌘Z**.
- **Code Beautifier:** Integrated Artistic Style (AStyle 2.06) with GNU, K&R, and Allman formatting presets.
- **Background Grep:** Search text across project files asynchronously with an instant Stop button.
- **Retina & Liquid Glass Icon:** Vector icon layers in `resources/Quincy.icon` (Icon Composer format) compiled into `Assets.car` with fallback `Quincy.icns`.
- **Project System:** Plain text `.prj` files (`Target=`, `Type=Console|Library|Dylib`, `File=`).

---

### Building

Only Apple Command Line Tools are required (`xcode-select --install`):

```bash
./build.sh
```

This compiles a native binary (`arm64`, `-O2 -flto`, ad-hoc signed) into:
```
build/Quincy 2005.app
```

> [!NOTE]
> If macOS restricts the debugger from attaching to processes, enable developer mode once in Terminal:
> ```bash
> sudo DevToolsSecurity -enable
> ```

---

### How to Use

| Action | Shortcut | Description |
|---|---|---|
| **Open File** | **⌘O** or File ▸ Open | Open `.c`, `.cpp`, `.h`, or `.prj` |
| **Build** | **⌘B** or **F6** | Compile the current file or project |
| **Run** | **⌘R** or **F9** | Run the target executable in console |
| **Toggle Breakpoint** | **F2** or Click Line # | Add / remove breakpoint at current line |
| **Step Into / Over** | **F7** / **F8** | Step through code in debugger |
| **Step Out** | **⇧F7** | Step out of current function |
| **Watch Window** | **⌥⌘0** | Open Watch inspector to monitor variables |
| **Examine** | **⌃⌘E** | Quick expression evaluation |
| **Documentation** | **F1** | Open User's Guide in browser |
| **Examples** | **F4** | Browse Quincy example programs |

---

### Key Differences from Windows Original

1. **Toolchain:** `clang` replaces `gcc`/`MinGW`, and `lldb` replaces `gdb`. Compiler flags are automatically mapped (e.g., `-gstabs` → `-g`, `-O4` → `-Os`).
2. **Dependencies:** Header dependencies are computed on the fly by Clang (`-MMD`) and stored cleanly in `~/Library/Caches` rather than cluttering project folders.
3. **Libraries:** Static libraries are archived with `ar rcs` (including symbol tables required by macOS `ld`), and DLL project types output macOS `.dylib`.
4. **UI Architecture:** Windows MDI layout is modernized into AppKit tabs, unified toolbar, and side inspector.
5. **Windows-only Libraries:** Win32 GUI, WinBGIm, koolplot, FLTK, Resource Editor, and FLUID are visually present in menus for compatibility reference but inactive under macOS.

---

### Performance & Verification

- **Launch Time:** ~0.4 seconds.
- **Memory Footprint:** ~64 MB.
- **Leaks Check:** 0 memory leaks detected.
- **Tested Scenarios:** Full debug cycle (breakpoints, stepping, watch, frame variable inspect, runtime expressions), multi-file C/C++ projects, static `.a` and dynamic `.dylib` targets, bracket matching, macros, undo/redo, printing to PDF, session restoration.

---

<br>

<a name="quincy-2005-для-macos-apple-silicon-ru"></a>

<div align="center">

[English](#quincy-2005-for-macos-apple-silicon) | **Русский**

</div>

---

## Quincy 2005 для macOS (Apple Silicon) [RU]

Переписанная на **Objective-C + AppKit** IDE **Quincy 2005 v1.3** (оригинальный автор — Al Stevens). Выглядит как нативное приложение macOS: сайдбар, вкладки документов, системный тулбар, внизу панель сборки и консоли, справа инспектор Watch, окно Settings. Все команды оригинала сохранены в меню и на тулбаре.

---

### Возможности

- **Нативный компилятор:** Вместо устаревшего MinGW используется Apple Clang с автоматическим подсчётом зависимостей от заголовков (`-MMD`).
- **Отладчик LLDB:** Полноценная интеграция с системным отладчиком macOS взамен GDB. Точки останова кликом по номеру строки или клавишей **F2**, просмотр переменных в инспекторе Watch (**⌥⌘0**), окно Examine (**⌃⌘E**) и строка ввода прямых команд lldb во вкладке Console.
- **Собственная консоль:** Программа запускается в отдельном окне консоли, по завершении выводится классическое `Press Enter to return to Quincy...`.
- **Вкладки и окна:** Документы открываются во вкладках; пункт **Window ▸ New Window** открывает второе окно с тем же файлом (общий текст, история Undo и точки останова).
- **Макросы:** Запись и воспроизведение нажатий клавиш в редакторе (включая стрелки и Enter); воспроизведённый макрос отменяется одним нажатием **⌘Z**.
- **Форматирование кода:** Встроенный AStyle 2.06 с пресетами GNU, K&R и Allman.
- **Фоновый Grep:** Быстрый многопоточный поиск по файлам проекта с возможностью прерывания кнопкой Stop.
- **Векторная иконка:** Слои SVG в формате Icon Composer (`resources/Quincy.icon`) собираются в `Assets.car` со стилем Liquid Glass и запасным `Quincy.icns` для старых версий macOS.
- **Проекты:** Текстовый формат `.prj` (`Target=`, `Type=Console|Library|Dylib`, `File=`).

---

### Сборка

Для сборки достаточно бесплатных Command Line Tools (`xcode-select --install`):

```bash
./build.sh
```

В результате создаётся готовый бандл (`arm64`, `-O2 -flto`, ad-hoc подпись):
```
build/Quincy 2005.app
```

> [!NOTE]
> Если система блокирует подключение отладчика к процессам, один раз выполните в Терминале:
> ```bash
> sudo DevToolsSecurity -enable
> ```

---

### Горячие клавиши и управление

| Действие | Сочетание | Описание |
|---|---|---|
| **Открыть файл** | **⌘O** или File ▸ Open | Открыть `.c`, `.cpp`, `.h` или файл проекта `.prj` |
| **Сборка** | **⌘B** или **F6** | Компиляция текущего файла или активного проекта |
| **Запуск** | **⌘R** или **F9** | Запуск собранной программы в окне консоли |
| **Точка останова** | **F2** или клик по номеру | Поставить / снять точку останова на строке |
| **Шаг с заходом / обходом** | **F7** / **F8** | Пошаговое выполнение в отладчике |
| **Шаг с выходом** | **⇧F7** | Выход из текущей функции |
| **Окно Watch** | **⌥⌘0** | Инспектор переменных и выражений |
| **Examine** | **⌃⌘E** | Быстрое вычисление значения переменной |
| **Справка** | **F1** | User's Guide в браузере прямо из бандла |
| **Примеры** | **F4** | Каталог примеров кода Quincy |

---

### Отличия от Windows-оригинала

1. **Тулчейн:** Вместо MinGW используется `clang`, вместо gdb — `lldb`. Флаги транслируются автоматически: `-gstabs` → `-g`, `-O4` → `-Os`, исключён `-fshort-enums`.
2. **Зависимости:** Зависимости от заголовков считает сам clang (`-MMD`). Списки хранятся в `~/Library/Caches`, не засоряя исходники, и не выводятся в лог сборки.
3. **Библиотеки:** Для статических библиотек вызывается `ar rcs` (линкеру macOS нужен индекс символов). Проекты типа DLL собираются в нативный `.dylib`.
4. **Интерфейс:** Оконный интерфейс MDI заменён на удобные вкладки документов и современный тулбар в стиле macOS.
5. **Специфичные библиотеки Windows:** Win32 GUI, WinBGIm, koolplot, FLTK, Resource Editor и FLUID сохранены в меню для совместимости, но неактивны под macOS.

---

### Проверка стабильности и производительности

- **Время запуска:** ~0,4 секунды.
- **Потребление памяти:** ~64 МБ.
- **Утечки:** 0 утечек памяти (`leaks`).
- **Протестировано:** Полный цикл отладки (breakpoints, Step Into/Over/Out, Watch `a := 42`, вычисление выражений `expr`, Stop), проекты из нескольких `.cpp` и `.h`, сборка `.a` и `.dylib`, парность скобок, макросы, Undo/Redo, Beautifier, Grep, экспорт в PDF, сохранение и восстановление сессии при перезапуске.

---

[▲ Back to top / Наверх](#quincy-2005-for-macos-apple-silicon)
