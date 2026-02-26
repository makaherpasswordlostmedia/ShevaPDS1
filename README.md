# Imlac PDS-1 — iOS

Полный порт эмулятора Imlac PDS-1 (1974) с Android на iOS, написанный на Swift + UIKit.

## Файлы

| Файл | Описание |
|------|---------|
| `Machine.swift` | Ядро эмулятора — MP + DP процессоры, 4096 слов RAM |
| `Demos.swift` | Демо-программы: звёзды, волны, Lissajous, Spacewar и др. |
| `CrtView.swift` | Рендерер — фосфорный CRT эффект через Core Graphics |
| `MazeWarGame.swift` | Maze War 1974 — 3D шутер с AI и мультиплеером |
| `NetSession.swift` | UDP LAN мультиплеер по WiFi (порты 7474/7475) |
| `EmulatorViewController.swift` | Главный экран — CRT + панель управления |
| `AppDelegate.swift` | Точка входа приложения |

## Сборка

### Xcode (локально)
1. Открыть `ImlacPDS1.xcodeproj`
2. Выбрать симулятор или устройство
3. Cmd+R

### GitHub Actions CI
Push в `main` — автоматически собирает Debug на симуляторе и Release архив.

## Мультиплеер (Maze War LAN)

- Оба устройства в **одной WiFi сети**
- Нажми **HOST** на первом устройстве
- Нажми **JOIN** на втором
- Автоматически находят друг друга через UDP broadcast
- Порты: 7474 (игра), 7475 (поиск)
- Чат встроен в боковую панель

## Управление

| Кнопка | Действие |
|--------|---------|
| ▲ / W | Вперёд |
| ▼ / S | Назад |
| ◀ / A | Повернуть влево |
| ▶ / D | Повернуть вправо |
| B / A / SPACE | Огонь |
| ⌨ KBD | Переключить виртуальную клавиатуру |

## Требования

- iOS 15.0+
- iPhone или iPad (landscape)
- Xcode 15 / Swift 5.9
