#!/bin/bash

# Останавливаем скрипт, если произойдет ошибка
set -e

echo "Установка Arch Linux + Niri"

# Просим sudo сразу, чтобы потом скрипт не останавливался
sudo -v
#1
echo -e "\n[1/7] Оболочка Niri, Kitty и тд"
sudo pacman -S --needed --noconfirm niri kitty wayland polkit-gnome ttf-jetbrains-mono-nerd base-devel fish starship ly git brightnessctl playerctl
# Я решил вынести приложения в отдельное
sudo pacman -S --needed --noconfirm firefox fastfetch nano obsidian telegram-desktop code tree

#2
echo -e "\n[2/7] Ставим yay"
if ! command -v yay &> /dev/null; then
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    cd -
    rm -rf /tmp/yay
else
    echo "yay уже установлен, скип."
fi
#3
echo -e "\n[3/7] Качаем пакеты из yay"
yay -S --needed --noconfirm dms-shell-niri dms-shell dgop dsearch-bin vicinae-bin nautilus
# Сюда тоже приложения 
yay -S --needed --noconfirm karing-bin tg-ws-proxy-bin
#4
echo -e "\n[4/7] Копируем конфиги"
# Копируем всё из папки .config репозитория в системную ~/.config
cp -r .config/* ~/.config/
# Копируем настройки ly в системную папку (требует sudo)
sudo cp -r etc/ly /etc/
echo "Конфиги есть, ура"
#5
echo -e "\n[5/7] Ставим нормальный MineGrub"
# Скачиваем и ставим первую тему
git clone https://github.com/Lxtharia/minegrub-theme.git /tmp/minegrub-theme
sudo mkdir -p /boot/grub/themes
sudo cp -r /tmp/minegrub-theme/minegrub /boot/grub/themes/
# Скачиваем и ставим вторую тему
git clone https://github.com/Lxtharia/minegrub-world-sel-theme.git /tmp/minegrub-world-sel-theme
sudo cp -r /tmp/minegrub-world-sel-theme/minegrub-world-selection /boot/grub/themes/
# Очищаем временные файлы, пока пока
rm -rf /tmp/minegrub-theme /tmp/minegrub-world-sel-theme

# Прописываем тему world-selection в GRUB
sudo sed -i 's|^GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/minegrub-world-selection/theme.txt"|' /etc/default/grub
# Генерируем новый загрузочный файл
sudo grub-mkconfig -o /boot/grub/grub.cfg
#6
echo -e "\n[6/7] Делаем нормальный lockscreen manedger ly и включаем vicinae"
sudo systemctl set-default graphical.target
sudo systemctl enable ly@tty2.service
systemctl --user enable --now vicinae || echo "vicinae включен (запустится при входе)"
#7
echo -e "\n[7/7] Ставим Fish по умолчанию"
if [ "$SHELL" != "/usr/bin/fish" ]; then
    chsh -s /usr/bin/fish
fi


echo "Установка завершена, лол"
