# LAN WATCH

**Your local network, in view.**

A network presence dashboard for OpenWrt and OpenMPTCProuter. Designed with OMR in mind, and available for compatible OpenWrt installations.

[Italiano](#italiano) · [English](#english)

## Versione / Version

**v0.1** è la numerazione iniziale del progetto. Le build sperimentali precedentemente pubblicate come 1.0, 1.0.1 e 1.0.2 sono state rinumerate; le prove storiche sotto mantengono i numeri originali.

**v0.1** is the initial project version. Earlier experimental builds were published as 1.0, 1.0.1 and 1.0.2 before renumbering; historical test results retain their original version numbers.

## Italiano

LAN WATCH mostra i dispositivi rilevati sulla rete locale, con IP, MAC, nome quando disponibile, ultima risposta ed eventi di mancata risposta e ritorno. È pensato per OpenMPTCProuter (OMR) e può essere installato anche su sistemi OpenWrt compatibili: non tutti i router o le configurazioni sono ancora stati testati.

### Come funziona

- Cerca dispositivi nella **sola rete IPv4 /24 selezionata**, inviando richieste **ARP** dalla relativa interfaccia. Non esegue ping ICMP verso Internet.
- Per cercare i nomi, può interrogare con **`dig`** l'indirizzo del gateway locale indicato durante l'installazione. Invia richieste DNS inverse PTR per gli IP rilevati, con ricorsione non richiesta. Il gateway deve conoscere i nomi e rispondere come DNS; se DNS e gateway sono diversi, questa versione non supporta un DNS fuori dalla /24 selezionata.
- Durante il monitoraggio, LAN WATCH non invia telemetria, non contatta servizi esterni e non cerca aggiornamenti. L'installazione può invece contattare i **repository APK già configurati sul router**, solo se servono le dipendenze `arping` o `dig`. Il collegamento GitHub nel pannello apre il profilo dell’autore solo se selezionato dall’utente. Il comportamento del gateway DNS e di altre applicazioni del router è indipendente dal monitor.
- Una mancata risposta ripetuta viene indicata come **non rilevato**. Non dimostra che il dispositivo sia spento. Se una scansione è completamente vuota e ci sono dispositivi già registrati, il programma conserva lo stato precedente e segnala un errore: questo può accadere anche se tutti i dispositivi sono davvero offline.

Un nome uguale non identifica necessariamente lo stesso dispositivo. Se un dispositivo cambia MAC può comparire come una nuova voce; ARP non permette di collegare con certezza le due identità. I record con MAC malformati vengono segnalati e non cancellati automaticamente.

ARP opera sul segmento locale: reti instradate, VLAN separate, isolamento Wi-Fi, dispositivi IPv6-only e MAC casuali possono limitare i risultati. I nomi possono mancare, essere generici o cambiare. Gli orari sono approssimati alla scansione; gli eventi mentre il monitor è fermo non sono ricostruibili. Lo storico degli eventi è limitato alle ultime 10.000 righe e un'interruzione durante la scrittura può causare eventi duplicati o mancanti.

### Vista dispositivi

Il pannello mostra **Online** e **Offline · ultime 24 ore**. Il contatore Offline usa una finestra mobile: non si azzera a un orario fisso, ma diminuisce quando l’ultima risposta di ciascun dispositivo raggiunge le 24 ore. Una voce Offline viene mostrata e conteggiata soltanto se la sua ultima risposta risale a meno di 24 ore; poi viene nascosta dalla vista principale, senza cancellare il record o gli eventi. Se lo stesso MAC ritorna, viene riconosciuto. Il filtro non libera spazio sul router. La sezione Attività recente mostra al massimo le ultime 30 disconnessioni e riconnessioni rilevate. Se la scansione non è aggiornata, i contatori non sono presentati come stato corrente.

### Intervallo di scansione

LAN WATCH punta ad avviare una scansione ogni **60 secondi**. Le scansioni non si sovrappongono e fra i cicli è prevista una pausa minima di 3 secondi; una scansione lunga può ritardare la successiva. Offline richiede tre scansioni consecutive senza risposta; il tempo effettivo dipende dalla durata delle scansioni e non è garantito. L'intervallo non è modificabile dal pannello.

### Accesso e sicurezza

Nelle nuove installazioni scegli la porta TCP del pannello: il valore proposto è **65335** sull'IP LAN scelto. Le installazioni precedenti senza porta configurata mantengono 59876. Il pannello è senza password. Non aprirlo sulla WAN o su Internet. Usalo soltanto sulla LAN fidata oppure tramite ZeroTier, Tailscale o un'altra VPN **già configurata e protetta**, se la tua configurazione consente di raggiungere quell'IP LAN. LAN WATCH non installa o configura VPN, non crea regole e **non modifica il firewall**. La porta alta non garantisce sicurezza e il solo ascolto sull'IP LAN non garantisce isolamento: verifica firewall, inoltri, accessi VPN e routing della tua rete. Chiunque raggiunga la pagina può leggere informazioni e storico.

### Compatibilità e installazione

Il controllo versioni ammette OpenWrt **25.12.x**, ImmortalWrt **25.12-SNAPSHOT** e OMR **v0.64.3-3K**. Questa è la lista delle versioni consentite dall'installer, non una garanzia di compatibilità con ogni build. **Questa versione resta sperimentale**: installazione e rimozione della 1.0.2 sono state provate su un router ImmortalWrt 25.12-SNAPSHOT e uno OpenWrt 25.12.5; la scansione è stata verificata su entrambi con la 1.0.1. Disconnessioni reali, riavvio e aggiornamento firmware non sono ancora verificati.

Sul router, come root, scarica il progetto in `/tmp/lanwatch` ed estrailo. Per questo passaggio servono accesso a Internet e supporto HTTPS in `wget`:

```sh
mkdir -p /tmp/lanwatch &&
wget -O /tmp/lanwatch/lanwatch.tar.gz https://github.com/fmase/LAN-WATCH/archive/refs/heads/main.tar.gz &&
tar -xzf /tmp/lanwatch/lanwatch.tar.gz -C /tmp/lanwatch &&
cd /tmp/lanwatch/LAN-WATCH-main
```

Se il download e l’estrazione sono riusciti, puoi prima provare l’anteprima senza modifiche:

```sh
sh lwinstall.sh --preview
```

Per installare:

```sh
sh lwinstall.sh
```

Il comando da usare è `lwinstall.sh`: gli script per le singole lingue sono richiamati automaticamente. `install.sh` resta disponibile per compatibilità con le istruzioni precedenti.

L'installer chiede italiano o inglese, individua la LAN e chiede quale usare se sono presenti più indirizzi `/24`. Chiede l'IP del gateway, ad esempio `192.168.0.1` o `192.168.1.254`; Invio disattiva le richieste DNS inverse. Se disponibili, i nomi possono comunque provenire dai lease DHCP locali. Chiede anche la porta TCP: Invio accetta `65335`. Al termine stampa l'indirizzo web esatto. Se il servizio è già installato, propone l’aggiornamento; per una nuova installazione si ferma se la porta è occupata.

Per aggiornare, scarica una versione successiva ed esegui il suo `sh lwinstall.sh`: se rileva LAN WATCH, mostra le versioni e chiede conferma. Conserva lingua, configurazione e storico e tenta il ripristino se la verifica fallisce. Gli aggiornamenti diretti tra versioni sono supportati dal programma, ma la compatibilità di eventuali futuri cambiamenti dei dati richiederà test e, se necessaria, una migrazione. Blackout e arresti forzati non garantiscono il ripristino. La procedura è stata simulata e provata su due router reinstallando la stessa versione; un passaggio reale tra versioni differenti non è ancora stato verificato.

Per disinstallare il programma, dalla cartella estratta esegui `sh disinstalla.sh` (se hai già svuotato `/tmp`, scarica ed estrai nuovamente il progetto): il servizio e la configurazione vengono rimossi; lo storico in `/root/lan-monitor-data` e le dipendenze rimangono. Per eliminare soltanto i file temporanei scaricati, esci dalla cartella ed esegui `rm -rf /tmp/lanwatch`. `/tmp` è temporanea e può essere svuotata al riavvio. La conservazione attraverso sysupgrade non è configurata né verificata. Consulta [AUDIT.md](AUDIT.md) prima di usare il progetto in modo continuativo.

### Licenza

LAN WATCH è disponibile con [PolyForm Noncommercial License 1.0.0](LICENSE.md). La licenza consente uso, modifiche e distribuzione per gli scopi non commerciali previsti dal testo, compresi gli usi personali specificati. Consente inoltre l'uso alle organizzazioni elencate nel testo, tra cui istituti educativi, enti pubblici e organizzazioni benefiche, indipendentemente dalla fonte dei finanziamenti. Al di fuori dei casi consentiti dalla licenza, l'uso commerciale non è autorizzato. Chi redistribuisce il software deve includere il testo o l'URL della licenza e il seguente avviso. Le restrizioni d'uso fanno sì che il progetto non sia open source secondo la definizione OSI.

Required Notice: Copyright 2026 fmase (@mcmas)

### Responsabilità

Nei limiti consentiti dalla legge, il software è fornito senza garanzie e il concedente della licenza non risponde dei danni, come specificato nel testo della licenza. Verifica funzionamento, firewall, copertura della rete e conservazione dei dati nel tuo ambiente prima di affidarti ai risultati. Utilizzalo soltanto su reti che sei autorizzato a monitorare.

## English

LAN WATCH displays devices detected on a local network, including IP, MAC, name when available, last response, and missed-response/recovery events. It is designed for OpenMPTCProuter (OMR) and can also be installed on compatible OpenWrt systems; not every router or configuration has been tested.

### How it works

- It discovers devices on the **selected IPv4 /24 network only** using **ARP requests** on the corresponding interface. It does not send ICMP pings to the Internet.
- For names it can use **`dig`** to ask the selected local gateway for PTR reverse DNS records for detected IPs, without requesting recursion. The gateway must know the names and answer local DNS queries. If your DNS server is separate from the gateway, this version does not support a DNS address outside the selected /24.
- During monitoring, LAN WATCH contains no telemetry, calls to external services, or update requests. The installer may contact the router's **configured APK repositories** only if the `arping` or `dig` dependencies are missing. The GitHub link in the dashboard opens the author's profile only when clicked. The behavior of the DNS gateway and other router applications is independent of this monitor.
- A device that repeatedly fails to respond is marked **not detected**. This does not prove that it is switched off. If a scan is entirely empty and devices are already recorded, the previous state is preserved and an error is raised, even if every device is actually offline.

The same hostname does not necessarily identify the same device. If a device changes its MAC address it may appear as a new entry; ARP cannot reliably link the two identities. Malformed MAC records are reported and not automatically deleted.

ARP operates on the local segment: routed networks, separate VLANs, Wi-Fi isolation, IPv6-only devices, and randomized MAC addresses can limit discovery. Names can be absent, generic, or change. Timestamps approximate the scan time; events while the monitor is stopped cannot be reconstructed. Event history is limited to the most recent 10,000 lines; interruption during writes can cause missing or duplicate events.

### Device view

The dashboard shows **Online** and **Offline · last 24 hours**. The Offline counter uses a rolling window: it does not reset at a fixed time, but decreases when each device’s last response reaches 24 hours old. An offline entry is shown and counted only while its last response is less than 24 hours old; it is then hidden from the main view without deleting the record or events. If the same MAC returns, it is recognized. This display filter does not free router storage. Recent activity shows up to the last 30 detected disconnections and reconnections. If scanning is stale, the counters are not presented as current state.

### Scan interval

LAN WATCH aims to start a scan every **60 seconds**. Scans do not overlap and a minimum 3-second pause separates cycles; a long scan can delay the next one. Offline requires three consecutive missed scans; actual detection time depends on scan duration and is not guaranteed. The dashboard does not expose an interval setting.

### Access and security

For new installations, choose the dashboard TCP port: the suggested default is **65335** on the selected LAN IP. Existing installations without a configured port retain 59876. The dashboard has no password. Do not expose it on the WAN or Internet. Use it only on a trusted LAN or through an **already configured and secured** ZeroTier, Tailscale, or other VPN, if your setup allows access to that LAN IP. LAN WATCH does not install or configure a VPN, create rules, or **modify the firewall**. A high port number does not provide security and binding to a LAN IP alone does not guarantee isolation: check your firewall, port forwarding, VPN access, and routing. Anyone who can reach the dashboard can read device information and history.

### Compatibility and installation

The version check allows OpenWrt **25.12.x**, ImmortalWrt **25.12-SNAPSHOT**, and OMR **v0.64.3-3K**. These are allowed targets, not a guarantee of compatibility with every build. **This version remains experimental**: installation and removal of 1.0.2 were tested on one ImmortalWrt 25.12-SNAPSHOT router and one OpenWrt 25.12.5 router; scanning was verified on both with 1.0.1. Actual disconnects, reboot, and firmware upgrades have not yet been verified.

On the router, as root, download the project into `/tmp/lanwatch` and extract it. This step requires Internet access and HTTPS support in `wget`:

```sh
mkdir -p /tmp/lanwatch &&
wget -O /tmp/lanwatch/lanwatch.tar.gz https://github.com/fmase/LAN-WATCH/archive/refs/heads/main.tar.gz &&
tar -xzf /tmp/lanwatch/lanwatch.tar.gz -C /tmp/lanwatch &&
cd /tmp/lanwatch/LAN-WATCH-main
```

If the download and extraction succeeded, you can first inspect the optional preview without making changes:

```sh
sh lwinstall.sh --preview
```

To install:

```sh
sh lwinstall.sh
```

Use `lwinstall.sh` to start: it automatically invokes the selected language script. `install.sh` remains available for compatibility with older instructions.

The installer asks for Italian or English, detects the LAN, and asks which `/24` address to use if more than one is present. It asks for the gateway IP, such as `192.168.0.1` or `192.168.1.254`; press Enter to disable reverse DNS lookups. Names can still come from local DHCP leases, when available. It also asks for the TCP port: press Enter to accept `65335`. It then prints the exact dashboard URL. If the service is already installed, it offers an update; for a new installation, it stops if the port is occupied.

To update, download a later release and run its `sh lwinstall.sh`: if LAN WATCH is installed, it shows both versions and asks for confirmation. It preserves language, configuration and history, and attempts to restore the previous version if verification fails. Direct upgrades are supported by the updater, but future data-format changes will require compatibility testing and migrations if needed. Recovery is not guaranteed after power loss or forced termination. This procedure was simulated and tested on two routers by reinstalling the same version; an actual upgrade between different versions has not yet been verified.

To uninstall, run `sh disinstalla.sh` from the extracted folder (download and extract the project again if `/tmp` has already been cleared): the service and configuration are removed; history in `/root/lan-monitor-data` and dependencies remain. To remove only the downloaded temporary files, leave that folder and run `rm -rf /tmp/lanwatch`. `/tmp` is temporary and may be cleared on reboot. Persistence through sysupgrade is neither configured nor verified. Read [AUDIT.md](AUDIT.md) before continuous use.

### License

LAN WATCH is available under the [PolyForm Noncommercial License 1.0.0](LICENSE.md). It permits use, modification, and distribution for the noncommercial purposes in its terms, including the specified personal uses. It also permits use by the organizations listed in the license, including educational institutions, government institutions, and charitable organizations, regardless of funding sources. Commercial use outside the cases permitted by the license is not authorized. Anyone redistributing the software must include the license text or URL and the following notice. These use restrictions mean the project is not open source under the OSI definition.

Required Notice: Copyright 2026 fmase (@mcmas)

### Disclaimer

To the extent allowed by law, the software is provided without warranties and the licensor is not liable for damages, as specified in the license. Verify its behavior, firewall rules, network coverage, and data retention in your own environment before relying on the results. Use it only on networks you are authorized to monitor.

---

**Made by [@fmase on GitHub](https://github.com/fmase)**

Se LAN WATCH ti piace, lascia una **⭐ Star**, segui l'autore e, se vuoi sostenere i progetti futuri, offrimi un caffè: contattami su Telegram per sapere come fare. Grazie!

If you like LAN WATCH, please **⭐ Star** the repository, follow the author, and, if you'd like to support future projects, buy me a coffee: contact me on Telegram for donation details. Thank you!
