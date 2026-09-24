# Imlac PDS-1 — 32-bit iOS 7.1 (armv7)

Objective-C порт эмулятора Imlac PDS-1 (1974) для 32-битных устройств на iOS 7.x
(iPhone 4/4s/5/5c, iPad 2/3/4/mini 1 и т.д.). Минимальная версия — iOS 7.0, приложение
работает и на более новых системах (проверялось по коду до iOS 9.3).

## Сборка

GitHub Actions (`.github/workflows/ios-build.yml`) собирает `.ipa` и `.deb` через Theos на ubuntu-latest:
toolchain L1ghtmann + iPhoneOS 9.3 SDK (Sn0wCooder/theos-sdks), `ARCHS = armv7`,
`TARGET = iphone:clang:9.3:7.0` (SDK 9.3, deployment target 7.0).

Локально: `export THEOS=~/theos && make package FINALPACKAGE=1`

Артефакт: `packages/*.ipa` и `packages/*.deb`.

## Особенности iOS 7

- `UIScreen.bounds` до iOS 8 всегда портретный, поэтому раскладка берёт длинную сторону как ширину.
- Очередь сети использует `DISPATCH_QUEUE_PRIORITY_HIGH` (QoS-классы есть только с iOS 8).
- В `Resources/` лежат чёрные `Default*.png`, чтобы iPhone 5/5s/5c запускал приложение на весь 4" экран.

## Производительность (iPad 2 и другие A5)

`CrtView` рендерит кадр в непрозрачный BGRA-битмап и отдаёт его в Core Animation как `layer.contents`
(без `drawRect:`). Сканлайны и виньетка запекаются один раз в отдельный слой. Векторы группируются по яркости
и рисуются несколькими вызовами `CGContextStrokeLineSegments` вместо 3 обводок на вектор.
Если кадр не укладывается в бюджет, разрешение рендера автоматически снижается 1.0x → 0.75x → 0.5x.

## Управление

| Кнопка | Действие |
|--------|---------|
| ▲ / W | Вперёд |
| ▼ / S | Назад |
| ◀ / A | Повернуть влево |
| ▶ / D | Повернуть вправо |
| B / A / SPACE | Огонь |

## Мультиплеер (Maze War LAN)

Оба устройства в одной WiFi сети; HOST на первом, JOIN на втором. UDP порты 7474 (игра) / 7475 (поиск).
