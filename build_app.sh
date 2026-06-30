#!/bin/bash

# Скрипт для сборки полноценного macOS-приложения (.app) и упаковки его в .zip

# Папка проекта
PROJECT_DIR="/Users/arturbakhtygereyev/dev/gif-widget"
APP_NAME="gifwidget"
APP_DIR="$PROJECT_DIR/$APP_NAME.app"

echo "1. Компиляция исходного кода Swift..."
swiftc -O "$PROJECT_DIR/main.swift" -o "$PROJECT_DIR/$APP_NAME"

if [ $? -ne 0 ]; then
    echo "Ошибка компиляции!"
    exit 1
fi

echo "2. Создание структуры папок .app приложения..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

echo "3. Копирование бинарного файла..."
cp "$PROJECT_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "4. Создание файла Info.plist..."
cat <<EOF > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>dev.artur.$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "5. Создание ZIP-архива для удобной отправки..."
rm -f "$PROJECT_DIR/$APP_NAME.zip"
zip -q -r "$PROJECT_DIR/$APP_NAME.zip" "$APP_NAME.app"

echo "Готово! Приложение собрано: $APP_DIR"
echo "Архив для отправки готов: $PROJECT_DIR/$APP_NAME.zip"
echo "Теперь любой пользователь может просто скачать ZIP, распаковать его и запустить приложение двойным кликом!"
