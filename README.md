# Игры Pixel Quest

Репозиторий содержит исходный код игр проекта [Pixel Quest](https://pixelquest.ru), написанных на языке Lua.
Здесь представлены исходники не всех игр проекта, часть игр по-прежнему написана на Go и со временем будет также перенесена на Lua.

#### Шаблон скрипта с подробными комментариями находится в файле [template.lua](https://github.com/pixel-quest/pixel-games/blob/main/template.lua)
Скрипты обслуживаются виртуальной машиной [GopherLua](https://github.com/yuin/gopher-lua), написанной на языке Go.
На момент Февраля 2024г используется **GopherLua v1.1.1** (Lua5.1 + goto statement in Lua5.2).

### Список текущих механик Pixel Quest:
- Заставка **Радуга** (Lua) – [rainbow_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/rainbow_v1.lua)
- Заставка **Круги на воде** (Go) – требуется переписать на Lua
- Заставка **Марио** (Go) – требуется переписать на Lua
- **Пиксель дуэль** (Lua) – [pixel_duel_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/pixel_duel_v1.lua)
- **Пол – это лава** (Go) – самая жирная и тяжёлая механика, под неё имеется конструктор уровней, требуется переписать на Lua
- **Перебежка** (Go) – требуется переписать на Lua
- **Море волнуется** (Go) – требуется переписать на Lua
- **Классики** (Go) – требуется переписать на Lua
- **Безопасный цвет** (Go) – требуется переписать на Lua
- **Найди цвет** (Go) – требуется переписать на Lua

### Приоритетная очередь механик на разработку:
- **Танцы** – в процессе разработики
- **Черепашьи бега** – игроки быстро попеременно нажимают на пиксели, а на экране бегут черепашки
- **Лава дуэль** – игровое поле поделено на зоны, где отдельные игроки соревнуются на скорость
- **Змейка** – аналог Пиксель дуэль против компьютерной змейки
- **Повтори рисунок** – нужно на скорость нарисовать рисунок по шаблону 
- **Вирус** – игроки захватывают поле своим цветом
- **Пакман** – собираем синие в лабиринте с бегающим красным пикселем
- **Арканоид** – платформой отбиваем мячик, выбивая блоки на противоположной стороне
- **Пинг-понг** – платформами отбиваем мячик друг другу
- **Классики-эстафета** – игроки делятся на команды и проходят классики на скорость в виде эстафеты
