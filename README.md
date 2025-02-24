<img align="right" src="https://github.com/pixel-quest/pixel-games/raw/main/img/logo.png" height="200">

# 🕹 Игры [Pixel Quest](https://pixelquest.ru)

Репозиторий содержит исходный код игр проекта [Pixel Quest](https://pixelquest.ru), написанных на языке Lua.
Здесь представлены исходники не всех игр проекта, часть игр по-прежнему написана на Go и со временем будет также перенесена на Lua.

### Следить за технической стороной проекта Pixel Quest можно в телеграм канале [@pixel_quest](https://t.me/pixel_quest)

Скрипты обслуживаются виртуальной машиной [GopherLua](https://github.com/yuin/gopher-lua), написанной на языке Go.
На данный момент используется **GopherLua v1.1.1** (Lua5.1 + оператор goto из Lua5.2).

См. базовое описание структуры скрипта и понятийный аппарат в [Wiki](https://github.com/pixel-quest/pixel-games/wiki)  
Шаблон скрипта с подробными комментариями – [template_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/template_v1/template_v1.lua)

### Отладочная платформа
Для написания и отладки кода игр у нас есть специальная web-платформа, доступ к которой можно получить, вступив в группу телеграм [@pixel_quest_games](https://t.me/pixel_quest_games)

<img src="https://github.com/pixel-quest/pixel-games/raw/main/img/floor-is-lava.png">

### Список текущих механик Pixel Quest
- **Go**
  - **Пол – это лава** – *собираем синие, избегая лавы (самая жирная и тяжёлая механика, под неё имеется визуальный конструктор уровней)*
- **Lua**
  - Заставка **Радуга** – *переливающийся пол* [rainbow_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/rainbow_v1/rainbow_v1.lua)
  - Заставка **Марио** – *рисунок Марио во весь пол с переливающимся фоном* [mario_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/mario_v1/mario_v1.lua)
  - Заставка **Круги на воде** – *расходящиеся круги от шагов* [water_circles_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/water_circles_v1/water_circles_v1.lua)
  - Заставка **Супергерои** – *рисунки мультяшных супергероев* [heroes_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/heroes_v1/heroes_v1.lua)
  - **Пиксель дуэль** – *собираем свой цвет быстрее соперника* [pixel_duel_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/pixel_duel_v1/pixel_duel_v1.lua)
  - **Море волнуется** – *соревнуемся и собираем на цветном поле свой цвет* [sea_is_rough_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/sea_is_rough_v1/sea_is_rough_v1.lua)
  - **Безопасный цвет** – *нужно успеть встать на безопасный цвет, прежде чем поле загорится красным* [safe_color_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/safe_color_v1/safe_color_v1.lua)
  - **Пинг-понг** – *платформами отбиваем мячик друг другу* [ping_pong_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/ping_pong_v1/ping_pong_v1.lua)
  - **Танцы** – *ловим пиксели под веселую корейскую музыку* [dance_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/dance_v1/dance_v1.lua)
  - **Найди цвет** – *на разноцветном поле требуется найти нужный цвет* [find_color_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/find_color_v1/find_color_v1.lua)
  - **Защита базы** – *по центру карты стоит база, которую защищают игроки* [tower_defence_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/tower_defence_v1/tower_defence_v1.lua)
  - **Защита базы 2** – *попытка расширить игру за счёт перемещающегося поля* [tower_defence_v2.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/tower_defence_v2/tower_defence_v2.lua)
  - **Лава дуэль** – *игровое поле поделено на зоны, где отдельные игроки соревнуются на скорость* [lava_duel_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/lava_duel_v1/lava_duel_v1.lua)
  - **Эстафета** – *две команды соревнуются между собой на скорость прохождения* [classics_race_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/classics_race_v1/classics_race_v1.lua)
  - **Лабиринт** – *аналог Пакмана* [labyrinth_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/labyrinth_v1/labyrinth_v1.lua)
  - **Сапёр** – *соревновательная игра на запоминание рисунка мин* [minesweeper_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/minesweeper_v1/minesweeper_v1.lua)
  - **Перебежка** – *бегаем от кнопки к кнопке, перепрыгивая полоску лавы* [dash_v2.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/dash_v2/dash_v2.lua)
  - **Змейка** – *аналог Пиксель дуэли против компьютерной змейки* [snake_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/snake_v1/snake_v1.lua)
  - **Час пик** – *выведи машинку из затора в час пик*  [huarong_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/huarong_v1/huarong_v1.lua)
  - **Олимпиада** – *соревнования по разным механикам* [olympics_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/olympics_v1/olympics_v1.lua)
  - **Повтори рисунок** – *нужно на скорость нарисовать рисунок по шаблону* [match_the_picture_v1](https://github.com/pixel-quest/pixel-games/blob/main/games/match_the_picture_v1/match_the_picture_v1.lua)
  - **Хомяк** – *тупая кликалка на хомяка* [humster_rush_v1](https://github.com/pixel-quest/pixel-games/blob/main/games/humster_rush_v1/humster_rush_v1.lua)
  - **Рисовалка** – *тупая кликалка на хомяка* [сoloring_book_v1](https://github.com/pixel-quest/pixel-games/blob/main/games/сoloring_book_v1/сoloring_book_v1.lua)
  - **Вирус** – *игроки захватывают поле своим цветом* [conquest_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/conquest_v1/conquest_v1.lua)
  - **Уклонись** – *игроки должны уклоняться от разных эффектов* [dodge_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/dodge_v1/dodge_v1.lua)
  - **Классики** – *классики 3х6* [classics_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/classics_v1/classics_v1.lua)
  - **Проводник** – *игра на двоих по выводу пикселя из лабиринта* [maze_guide_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/maze_guide_v1/maze_guide_v1.lua)
  - **Рефлекс** – *игра на реакцию* [reflex_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/reflex_v1/reflex_v1.lua)
  - **Туман** – *игра к Хэллоуину: поле покрыто туманом, надо искать конфеты* [fog_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/fog_v1/fog_v1.lua)
  - **Тетрис** – *классический Тетрис* [tetris_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/tetris_v1/tetris_v1.lua)
  - **Рисовалка** – *рисовалка* [сoloring_book_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/сoloring_book_v1/сoloring_book_v1.lua)
  - **Стеклянный Мост** – *испытание Стеклянный Мост из Игры в кальмара* [crab_glass_bridge_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/crab_glass_bridge_v1/crab_glass_bridge_v1.lua)
  - **Генеративная Пол – это лава** – *Пол – это лава с генеративными эффектами* [lava_floor_random_v1.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/lava_floor_random_v1/lava_floor_random_v1.lua)
  - **Сапёр V2** – *соревновательный Сапёр с пересечением зон игроков* [minesweeper_v2.lua](https://github.com/pixel-quest/pixel-games/blob/main/games/minesweeper_v2/minesweeper_v2.lua)

## Ещё скриншоты
<img src="https://github.com/pixel-quest/pixel-games/raw/main/img/lua-ide.jpg">

<img src="https://github.com/pixel-quest/pixel-games/raw/main/img/rainbow.jpg">

<img src="https://github.com/pixel-quest/pixel-games/raw/main/img/ping-pong.png">

## Лицензия
**Игры Pixel Quest** распространяются по лицензии [CC BY-NC-SA 4.0](https://github.com/pixel-quest/pixel-games/blob/main/LICENSE)  
Коммерческое использование запрещено.  
Обязательно указание первоисточника.  
**Pixel Quest** © 2023−2025  
  
ООО "Пиксель Квест"  
ОГРН: 1235000071371  
ИНН: 5050159532  
КПП: 505001001  
