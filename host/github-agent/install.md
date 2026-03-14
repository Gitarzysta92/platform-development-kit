1️⃣ Zainstaluj runner jako service

W katalogu runnera uruchom:

sudo ./svc.sh install

To utworzy usługę systemową.

2️⃣ Uruchom usługę
sudo ./svc.sh start
3️⃣ Sprawdź status
sudo systemctl status actions.runner.*

lub dokładniej:

sudo systemctl status actions.runner.Gitarzysta92-solution-development-kit.*

Powinieneś zobaczyć:

Active: active (running)
4️⃣ Sprawdź czy uruchamia się przy starcie systemu
sudo systemctl is-enabled actions.runner.*

powinno zwrócić:

enabled
5️⃣ Restart w razie crasha

Możesz dodatkowo ustawić automatyczny restart:

sudo systemctl edit actions.runner.*

i dodać:

[Service]
Restart=always
RestartSec=5
6️⃣ Przydatne komendy
restart runnera
sudo ./svc.sh restart
zatrzymanie
sudo ./svc.sh stop
odinstalowanie
sudo ./svc.sh uninstall