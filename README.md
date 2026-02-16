# ☠️ SwiftReaper v2.1 - Guide d'Installation Complet

> **Le Faucheur de Pips** - Système de notifications Forex haute précision

---

## 📋 Table des matières

1. [Présentation](#-présentation)
2. [Fichiers inclus](#-fichiers-inclus)
3. [Installation MT5](#-installation-mt5)
4. [Installation MT4](#-installation-mt4)
5. [Configuration des notifications push](#-configuration-des-notifications-push)
6. [Paramètres du bot](#-paramètres-du-bot)
7. [Comment utiliser le bot](#-comment-utiliser-le-bot)
8. [Installer sur plusieurs paires](#-installer-sur-plusieurs-paires)
9. [Configuration du fuseau horaire](#-configuration-du-fuseau-horaire)
10. [Filtre News (MT4 uniquement)](#-filtre-news-mt4-uniquement)
11. [FAQ / Problèmes courants](#-faq--problèmes-courants)

---

## 🎯 Présentation

SwiftReaper est un **système de notifications** qui t'envoie des alertes sur ton téléphone quand :
- Un signal d'**ENTRÉE** est détecté (BUY ou SELL)
- Un signal de **SORTIE** est détecté (fermer la position)

### Stratégie utilisée :
| Élément | Détail |
|---------|--------|
| **Tendance** | EMA 50 sur H1 - Prix au-dessus = BUY only, en-dessous = SELL only |
| **Entrée** | RSI 14 sort de survente/surachat sur M5 + bougie de confirmation |
| **Sortie** | Engulfing, EMA 8 cassée, ou RSI en zone extrême |
| **Filtres** | Sessions London/NY, évite les news, évite lundi matin/vendredi soir |

### Ce que le bot NE FAIT PAS :
- ❌ Il n'ouvre PAS de positions automatiquement
- ❌ Il ne ferme PAS de positions automatiquement
- ✅ Il t'**ENVOIE DES NOTIFICATIONS** pour que TU décides

---

## 📁 Fichiers inclus

| Fichier | Description |
|---------|-------------|
| `SwiftReaper.mq5` | Version pour **MetaTrader 5** (calendrier économique intégré) |
| `SwiftReaper.mq4` | Version pour **MetaTrader 4** (filtre news manuel) |
| `README.md` | Ce guide |

---

## 🔧 Installation MT5

### Étape 1 : Localiser le dossier Experts

1. Ouvre **MetaTrader 5**
2. Va dans **Fichier → Ouvrir le dossier des données**
3. Navigue vers `MQL5/Experts/`

### Étape 2 : Copier le fichier

1. Copie le fichier `SwiftReaper.mq5` dans le dossier `MQL5/Experts/`

### Étape 3 : Compiler le code

1. Dans MT5, va dans **Outils → MetaQuotes Language Editor** (ou appuie sur F4)
2. Dans l'éditeur, double-clique sur `SwiftReaper.mq5` dans le panneau de gauche
3. Appuie sur **F7** (ou Compiler) pour compiler
4. Vérifie qu'il n'y a **0 erreurs** en bas

### Étape 4 : Attacher l'Expert au graphique

1. Retourne dans MT5
2. Va dans **Vue → Navigateur** (ou Ctrl+N)
3. Développe **Expert Advisors**
4. Fais un **glisser-déposer** de `SwiftReaper` sur le graphique de la paire souhaitée
5. Une fenêtre de paramètres s'ouvre - configure selon tes besoins
6. Clique sur **OK**

### Étape 5 : Activer le trading automatique

1. Clique sur le bouton **Algo Trading** dans la barre d'outils (doit être vert)
2. Ou va dans **Outils → Options → Expert Advisors** et coche "Autoriser le trading automatique"

---

## 🔧 Installation MT4

### Étape 1 : Localiser le dossier Experts

1. Ouvre **MetaTrader 4**
2. Va dans **Fichier → Ouvrir le dossier des données**
3. Navigue vers `MQL4/Experts/`

### Étape 2 : Copier le fichier

1. Copie le fichier `SwiftReaper.mq4` dans le dossier `MQL4/Experts/`

### Étape 3 : Compiler le code

1. Dans MT4, va dans **Outils → MetaQuotes Language Editor** (ou appuie sur F4)
2. Dans l'éditeur, ouvre `SwiftReaper.mq4`
3. Appuie sur **F7** pour compiler
4. Vérifie **0 erreurs**

### Étape 4 : Actualiser la liste

1. Retourne dans MT4
2. Dans le Navigateur (Ctrl+N), fais un **clic droit sur Expert Advisors → Actualiser**

### Étape 5 : Attacher au graphique

1. Glisse-dépose `SwiftReaper` sur le graphique
2. Dans l'onglet **Commun**, coche :
   - ✅ Autoriser le trading automatique
   - ✅ Autoriser l'importation de DLL (si demandé)
3. Configure les paramètres dans l'onglet **Entrées**
4. Clique **OK**

---

## 📱 Configuration des notifications push

Pour recevoir les alertes sur ton téléphone :

### Sur ton téléphone :

1. Télécharge l'app **MetaTrader 4** ou **MetaTrader 5** sur ton téléphone
2. Ouvre l'app
3. Va dans **Paramètres → Messages**
4. Note ton **MetaQuotes ID** (un code comme "A1B2C3D4")

### Sur MT4/MT5 Desktop :

1. Va dans **Outils → Options**
2. Onglet **Notifications**
3. Coche **Activer les notifications push**
4. Entre ton **MetaQuotes ID**
5. Clique sur **Tester** pour vérifier que ça fonctionne
6. Tu devrais recevoir une notification test sur ton téléphone

---

## ⚙️ Paramètres du bot

### Notifications
| Paramètre | Défaut | Description |
|-----------|--------|-------------|
| EnableNotifications | true | Activer les notifications push sur téléphone |
| EnableAlerts | true | Activer les alertes sonores sur PC |

### Timeframes
| Paramètre | Défaut | Description |
|-----------|--------|-------------|
| TF_Trend | H1 | Timeframe pour détecter la tendance |
| TF_Entry | M5 | Timeframe pour les signaux d'entrée/sortie |

### Indicateurs
| Paramètre | Défaut | Description |
|-----------|--------|-------------|
| EMA_Period | 50 | Période EMA pour la tendance (H1) |
| RSI_Period | 14 | Période RSI pour l'entrée (M5) |
| RSI_Oversold | 30 | Zone de survente RSI (signal BUY) |
| RSI_Overbought | 70 | Zone de surachat RSI (signal SELL) |
| EMA_Exit_Period | 8 | EMA rapide pour détecter la sortie |

### Filtres horaires (Bénin GMT+1)
| Paramètre | Défaut | Description |
|-----------|--------|-------------|
| BrokerGMTOffset | 0 | Décalage GMT de ton broker (voir section dédiée) |
| StartHour | 8 | Début des signaux (08h00 Bénin) |
| EndHour | 21 | Fin des signaux (21h00 Bénin) |
| FilterMonday | true | Éviter les signaux lundi avant 10h |
| FilterFriday | true | Éviter les signaux vendredi après 18h |

### Filtre News
| Paramètre | Défaut | Description |
|-----------|--------|-------------|
| FilterHighImpactNews | true (MT5) / false (MT4) | Filtrer les news à fort impact |
| NewsMinutesBefore | 30 | Minutes avant une news = pas de signal |
| NewsMinutesAfter | 30 | Minutes après une news = pas de signal |

---

## 🎮 Comment utiliser le bot

### Quand tu reçois "ENTRE BUY 🟢" ou "ENTRE SELL 🔴" :

1. **Ouvre MetaTrader** sur ton PC ou téléphone
2. **Ouvre un ordre** dans le sens indiqué
3. **Taille de position** : selon ton plan (ex: 0.01 à 0.05 lot pour 10€)
4. **Pas de SL/TP fixe** : attends le signal de sortie

### Quand tu reçois "SORS DU BUY/SELL" :

1. **Ferme ta position** immédiatement
2. **Ne réfléchis pas** - le bot a détecté un retournement
3. **Prends ce que le marché a donné**

### Règles d'or :

| Règle | Pourquoi |
|-------|----------|
| Entre UNIQUEMENT sur signal du bot | Pas d'improvisation |
| Sors UNIQUEMENT sur signal du bot | Pas d'émotions |
| 1 trade à la fois par paire | Pas de pyramidage hasardeux |
| Respecte le plan | La discipline fait le trader |

---

## 📊 Installer sur plusieurs paires

Tu peux mettre le bot sur plusieurs graphiques simultanément :

### Paires recommandées :
- EUR/USD
- GBP/USD
- USD/JPY
- USD/CHF
- XAU/USD (Or)

### Comment faire :

1. Ouvre un graphique pour chaque paire
2. Mets chaque graphique en **M5** (ou laisse, le bot gère)
3. Glisse-dépose SwiftReaper sur CHAQUE graphique
4. Chaque instance est indépendante

### Conseil :
Tu peux utiliser le paramètre `PairName` pour personnaliser le nom dans les notifications :
- EURUSD → "EUR/USD"
- XAUUSD → "GOLD"

---

## 🌍 Configuration du fuseau horaire

### Trouver le GMT de ton broker :

1. Regarde l'heure affichée dans MT4/MT5 (en haut à gauche du graphique)
2. Compare avec l'heure GMT actuelle (google "current GMT time")
3. Calcule la différence

### Exemples :
| Heure broker | Heure GMT | BrokerGMTOffset |
|--------------|-----------|-----------------|
| 12:00 | 12:00 | 0 |
| 14:00 | 12:00 | 2 |
| 15:00 | 12:00 | 3 |
| 10:00 | 12:00 | -2 |

### Brokers courants :
| Broker | GMT Offset typique |
|--------|-------------------|
| IC Markets | GMT+2 ou GMT+3 |
| XM | GMT+2 ou GMT+3 |
| FXTM | GMT+2 |
| Exness | GMT+0 |
| Deriv | GMT+0 |

> ⚠️ Vérifie toujours, ça peut changer avec l'heure d'été/hiver

---

## 📰 Filtre News (MT4 uniquement)

MT4 n'a pas de calendrier économique intégré. Tu dois configurer manuellement les heures de news importantes.

### Comment faire :

1. Va sur [Forex Factory](https://www.forexfactory.com/calendar) chaque matin
2. Note les heures des news **HIGH IMPACT** (drapeau rouge)
3. Convertis en heure Bénin (GMT+1)
4. Entre les heures dans les paramètres :
   - NewsTime1 = "1430" (pour 14h30)
   - NewsTime2 = "1600" (pour 16h00)
   - etc.

### Exemple :
```
NFP (Non-Farm Payrolls) à 13:30 GMT = 14:30 Bénin
→ NewsTime1 = "1430"
```

---

## ❓ FAQ / Problèmes courants

### "Je ne reçois pas de notifications"

1. Vérifie que ton MetaQuotes ID est correct
2. Vérifie que les notifications sont activées dans les options MT4/MT5
3. Vérifie que l'app mobile est installée et connectée
4. Vérifie que ton téléphone autorise les notifications de l'app

### "Le bot ne donne pas de signaux"

1. Vérifie que l'heure actuelle est dans la plage autorisée (8h-21h Bénin)
2. Vérifie que ce n'est pas lundi matin ou vendredi soir
3. Vérifie le panneau sur le graphique :
   - "Heures: ACTIF ✅" doit s'afficher
   - "News: OK ✅" doit s'afficher
4. Le marché n'est peut-être pas dans les bonnes conditions (RSI pas en zone extrême)

### "Le bot dit que je suis en position mais j'ai fermé manuellement"

**NOUVEAU v2.1 :** Le bot sauvegarde maintenant son état dans un fichier. Si tu fermes manuellement :

1. Va dans le dossier `MQL4/Files/` ou `MQL5/Files/`
2. Supprime le fichier `SwiftReaper_SYMBOLE_state.txt` (ex: `SwiftReaper_EURUSD_state.txt`)
3. Le bot redémarrera avec un état frais

Ou simplement : retire le bot du graphique et remets-le.

### "Je veux changer les paramètres"

1. Clique droit sur le graphique → **Expert Advisors → Propriétés**
2. Modifie les paramètres
3. Clique OK

### "Le panneau ne s'affiche pas"

1. Vérifie que les objets graphiques sont activés
2. Va dans **Graphiques → Objets → Afficher tout**

---

## ⚠️ Avertissement

Ce bot est un **outil d'aide à la décision**, pas une garantie de gains.

- Le trading comporte des risques
- Ne risque que ce que tu peux te permettre de perdre
- Les performances passées ne garantissent pas les résultats futurs
- **Les paramètres n'ont PAS été backtestés sur des données réelles**

---

## 🧪 Avant de trader en réel

### Option 1 : Démo (Recommandé)
1. Ouvre un compte démo chez ton broker
2. Installe le bot
3. Trade pendant 2-4 semaines
4. Note tes résultats

### Option 2 : Backtest manuel (Minimum)
1. Ouvre un graphique H1 + M5 sur EURUSD
2. Remonte 1 mois en arrière (F12 pour reculer bougie par bougie)
3. À chaque fois que tu vois les conditions réunies, note :
   - Signal d'entrée (RSI sort de 30, bougie verte en tendance haussière)
   - Signal de sortie (engulfing, EMA cassée, RSI 65+)
4. Compte les trades gagnants vs perdants

### Ce que tu cherches :
- **Winrate > 45%** avec un ratio gain/perte de 3:1 minimum
- **Pas plus de 5 pertes consécutives** (sinon c'est dur mentalement)

---

## 🆕 Nouveautés v2.1

### Sauvegarde d'état automatique
- L'état du bot est sauvegardé quand MT4/MT5 se ferme
- Au redémarrage, le bot restaure son état
- Fichier : `MQL4/Files/SwiftReaper_SYMBOLE_state.txt`

### Détection GMT automatique
- Le bot détecte automatiquement le fuseau horaire du broker
- Tu verras dans le log : "🌍 GMT Broker détecté: GMT+2"
- Plus besoin de configurer `BrokerGMTOffset` manuellement (sauf si tu veux forcer)

---

## 🔄 Changelog

### v2.1 (Janvier 2026)
- **NOUVEAU** : Sauvegarde d'état automatique (survit aux redémarrages)
- **NOUVEAU** : Détection automatique du GMT du broker
- Conditions d'entrée plus strictes (RSI < 35 + mèche forte)
- Engulfing pattern strict (vrai engulfing)
- Sortie : RSI >= 65 + bougie contre position

### v2.0 (Janvier 2026)
- Version initiale
- Système de notifications tendance + pullback
- Filtres horaires pour le Bénin
- Filtre news HIGH IMPACT

---

**Bon trading ! 🚀**

*SwiftReaper Development - 2026*
