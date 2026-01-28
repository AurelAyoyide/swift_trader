//+------------------------------------------------------------------+
//|                                              SwiftReaper.mq4     |
//|                        Copyright 2026, SwiftReaper Development   |
//|                                    https://www.swiftreaper.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, SwiftReaper Development"
#property link      "https://www.swiftreaper.com"
#property version   "2.00"
#property description "SwiftReaper v2.0 - Le Faucheur de Pips"
#property description "Système de notifications Forex - Tendance + Pullback"
#property strict

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum TREND_TYPE
{
   TREND_NONE,
   TREND_BULLISH,
   TREND_BEARISH
};

enum SIGNAL_TYPE
{
   SIGNAL_NONE,
   SIGNAL_BUY,
   SIGNAL_SELL,
   SIGNAL_EXIT_BUY,
   SIGNAL_EXIT_SELL
};

//+------------------------------------------------------------------+
//| PARAMÈTRES D'ENTRÉE                                              |
//+------------------------------------------------------------------+
// Notifications
extern bool     EnableNotifications = true;       // Activer les notifications push
extern bool     EnableAlerts = true;              // Activer les alertes sonores

// Timeframes
extern ENUM_TIMEFRAMES TF_Trend = PERIOD_H1;      // Timeframe tendance (H1)
extern ENUM_TIMEFRAMES TF_Entry = PERIOD_M5;      // Timeframe entrée (M5)

// Indicateurs
extern int      EMA_Period = 50;                  // Période EMA (tendance H1)
extern int      RSI_Period = 14;                  // Période RSI (entrée M5)
extern int      RSI_Oversold = 30;                // RSI survente (BUY zone)
extern int      RSI_Overbought = 70;              // RSI surachat (SELL zone)
extern int      EMA_Exit_Period = 8;              // EMA rapide pour sortie M5

// Filtres horaires (Heure du Bénin GMT+1)
extern int      BrokerGMTOffset = 0;              // Décalage GMT du broker (0 si GMT, 2 si GMT+2, etc.)
extern int      StartHour = 8;                    // Heure début (08h00 Bénin)
extern int      EndHour = 21;                     // Heure fin (21h00 Bénin)
extern bool     FilterMonday = true;              // Éviter lundi avant 10h
extern bool     FilterFriday = true;              // Éviter vendredi après 18h

// Filtre News (MT4: nécessite fichier externe ou désactivé)
extern bool     FilterHighImpactNews = false;     // Filtrer les news (nécessite config manuelle)
extern int      NewsMinutesBefore = 30;           // Minutes avant news (pas de signal)
extern int      NewsMinutesAfter = 30;            // Minutes après news (pas de signal)

// Heures de news à éviter manuellement (format HHMM, heure Bénin)
// Ajouter les heures de news importantes ici
extern string   NewsTime1 = "";                   // News 1 (ex: "1430" = 14h30)
extern string   NewsTime2 = "";                   // News 2
extern string   NewsTime3 = "";                   // News 3
extern string   NewsTime4 = "";                   // News 4
extern string   NewsTime5 = "";                   // News 5

// Paires (pour multi-chart)
extern string   PairName = "";                    // Nom personnalisé (vide = auto)

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                               |
//+------------------------------------------------------------------+
// État du système
TREND_TYPE g_currentTrend = TREND_NONE;
SIGNAL_TYPE g_lastSignal = SIGNAL_NONE;
bool g_inPosition = false;
SIGNAL_TYPE g_positionType = SIGNAL_NONE;

// Symbole
string g_symbol;
string g_displayName;

// Tracking bougies
datetime g_lastH1Candle = 0;
datetime g_lastM5Candle = 0;

// Nom objets graphiques
string g_panelName = "SwiftReaperPanel";

// Nom du fichier de sauvegarde d'état
string g_stateFileName;

// Décalage GMT calculé automatiquement
int g_detectedBrokerGMT = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialisation symbole
   g_symbol = Symbol();
   g_displayName = (PairName != "") ? PairName : g_symbol;
   
   // Nom du fichier de sauvegarde (unique par paire)
   g_stateFileName = "SwiftReaper_" + g_symbol + "_state.txt";
   
   // Détection automatique du GMT du broker
   g_detectedBrokerGMT = DetectBrokerGMTOffset();
   Print("🌍 GMT Broker détecté: GMT+", g_detectedBrokerGMT);
   
   // Charger l'état sauvegardé (si existe)
   LoadState();
   
   // Création panneau
   CreatePanel();
   
   // Timer pour vérification périodique
   EventSetTimer(1);
   
   // Détection tendance initiale
   DetectTrend();
   
   Print("✅ SwiftReaper v2.0 (MT4) initialisé sur ", g_displayName);
   Print("📍 Mode: Notifications uniquement");
   Print("⏰ Heures actives: ", StartHour, "h - ", EndHour, "h (Bénin)");
   
   if(g_inPosition)
      Print("🔄 État restauré: EN POSITION ", (g_positionType == SIGNAL_BUY ? "BUY" : "SELL"));
   
   if(FilterHighImpactNews)
      Print("⚠️ Filtre news activé - Configurez les heures manuellement");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Sauvegarder l'état avant de fermer
   SaveState();
   
   // Suppression objets graphiques
   ObjectsDeleteAll(0, g_panelName);
   
   // Arrêt timer
   EventKillTimer();
   
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Vérification nouvelles bougies fermées
   CheckNewCandles();
   
   // Mise à jour panneau
   UpdatePanel();
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdatePanel();
}

//+------------------------------------------------------------------+
//| Vérification nouvelles bougies FERMÉES                           |
//+------------------------------------------------------------------+
void CheckNewCandles()
{
   // Temps des bougies
   datetime h1Time = iTime(g_symbol, TF_Trend, 1);
   datetime m5Time = iTime(g_symbol, TF_Entry, 1);
   
   // Nouvelle bougie H1 FERMÉE
   if(h1Time > g_lastH1Candle && g_lastH1Candle != 0)
   {
      DetectTrend();
   }
   g_lastH1Candle = h1Time;
   
   // Nouvelle bougie M5 FERMÉE
   if(m5Time > g_lastM5Candle && g_lastM5Candle != 0)
   {
      // Vérifier les filtres avant de chercher des signaux
      if(IsTimeAllowed() && !IsHighImpactNewsNear())
      {
         if(g_inPosition)
            CheckExitSignal();
         else
            CheckEntrySignal();
      }
   }
   g_lastM5Candle = m5Time;
}

//+------------------------------------------------------------------+
//| Détection tendance H1 (sur bougies FERMÉES)                      |
//+------------------------------------------------------------------+
void DetectTrend()
{
   // EMA et prix sur bougie FERMÉE (index 1)
   double ema = iMA(g_symbol, TF_Trend, EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   double closePrice = iClose(g_symbol, TF_Trend, 1);
   
   TREND_TYPE previousTrend = g_currentTrend;
   
   if(closePrice > ema)
      g_currentTrend = TREND_BULLISH;
   else if(closePrice < ema)
      g_currentTrend = TREND_BEARISH;
   else
      g_currentTrend = TREND_NONE;
   
   // Log si changement de tendance
   if(previousTrend != g_currentTrend && previousTrend != TREND_NONE)
   {
      string trendText = (g_currentTrend == TREND_BULLISH) ? "HAUSSIÈRE 📈" : "BAISSIÈRE 📉";
      string msg = "🔄 SWIFT REAPER - " + g_displayName + " - Tendance: " + trendText;
      Print(msg);
   }
}

//+------------------------------------------------------------------+
//| Vérification signal d'ENTRÉE (M5 bougie FERMÉE)                  |
//+------------------------------------------------------------------+
void CheckEntrySignal()
{
   if(g_currentTrend == TREND_NONE) return;
   
   // RSI sur bougies fermées (index 1 et 2)
   double rsi = iRSI(g_symbol, TF_Entry, RSI_Period, PRICE_CLOSE, 1);
   double rsiPrev = iRSI(g_symbol, TF_Entry, RSI_Period, PRICE_CLOSE, 2);
   
   // Prix bougie fermée
   double closePrice = iClose(g_symbol, TF_Entry, 1);
   double openPrice = iOpen(g_symbol, TF_Entry, 1);
   double highPrice = iHigh(g_symbol, TF_Entry, 1);
   double lowPrice = iLow(g_symbol, TF_Entry, 1);
   
   // Bougie fermée précédente
   double closePricePrev = iClose(g_symbol, TF_Entry, 2);
   double openPricePrev = iOpen(g_symbol, TF_Entry, 2);
   
   // Vérification bougie de confirmation
   bool bullishCandle = closePrice > openPrice;
   bool bearishCandle = closePrice < openPrice;
   
   // Pin bar / bougie de rejet
   double bodySize = MathAbs(closePrice - openPrice);
   double upperWick = highPrice - MathMax(closePrice, openPrice);
   double lowerWick = MathMin(closePrice, openPrice) - lowPrice;
   
   bool bullishRejection = (lowerWick > bodySize * 1.5) && bullishCandle;
   bool bearishRejection = (upperWick > bodySize * 1.5) && bearishCandle;
   
   // === SIGNAL BUY ===
   if(g_currentTrend == TREND_BULLISH)
   {
      // RSI sort de survente (STRICT: était < 30, maintenant > 30)
      // OU RSI très bas (< 35) avec pin bar de rejet clair
      bool rsiExitOversold = (rsiPrev <= RSI_Oversold && rsi > RSI_Oversold);
      bool rsiWithStrongRejection = (rsi < 35 && bullishRejection && lowerWick > bodySize * 2.0);
      
      bool rsiCondition = rsiExitOversold || rsiWithStrongRejection;
      
      if(rsiCondition && bullishCandle)
      {
         SendEntrySignal(SIGNAL_BUY);
         return;
      }
   }
   
   // === SIGNAL SELL ===
   if(g_currentTrend == TREND_BEARISH)
   {
      // RSI sort de surachat (STRICT: était > 70, maintenant < 70)
      // OU RSI très haut (> 65) avec pin bar de rejet clair
      bool rsiExitOverbought = (rsiPrev >= RSI_Overbought && rsi < RSI_Overbought);
      bool rsiWithStrongRejection = (rsi > 65 && bearishRejection && upperWick > bodySize * 2.0);
      
      bool rsiCondition = rsiExitOverbought || rsiWithStrongRejection;
      
      if(rsiCondition && bearishCandle)
      {
         SendEntrySignal(SIGNAL_SELL);
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Vérification signal de SORTIE (M5 bougie FERMÉE)                 |
//+------------------------------------------------------------------+
void CheckExitSignal()
{
   // RSI
   double rsi = iRSI(g_symbol, TF_Entry, RSI_Period, PRICE_CLOSE, 1);
   
   // EMA Exit
   double emaExit = iMA(g_symbol, TF_Entry, EMA_Exit_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   double emaExitPrev = iMA(g_symbol, TF_Entry, EMA_Exit_Period, 0, MODE_EMA, PRICE_CLOSE, 2);
   
   // Prix
   double closePrice = iClose(g_symbol, TF_Entry, 1);
   double closePricePrev = iClose(g_symbol, TF_Entry, 2);
   double openPrice = iOpen(g_symbol, TF_Entry, 1);
   double openPricePrev = iOpen(g_symbol, TF_Entry, 2);
   
   bool shouldExit = false;
   string exitReason = "";
   
   // Calcul taille des bougies pour engulfing strict
   double bodySize1 = MathAbs(closePrice - openPrice);
   double bodySize2 = MathAbs(closePricePrev - openPricePrev);
   
   // === SORTIE POSITION BUY ===
   if(g_positionType == SIGNAL_BUY)
   {
      // 1. Bougie de retournement baissière FORTE (engulfing strict)
      bool bearishEngulfing = (closePrice < openPrice) &&  // Bougie baissière
                               (openPrice >= closePricePrev) && // Open >= close précédent
                               (closePrice <= openPricePrev) && // Close <= open précédent  
                               (bodySize1 > bodySize2 * 0.8);    // Corps significatif
      if(bearishEngulfing)
      {
         shouldExit = true;
         exitReason = "Engulfing baissier - SORS!";
      }
      
      // 2. Prix croise EMA 8 vers le bas
      bool emaCrossDown = (closePricePrev > emaExitPrev) && (closePrice < emaExit);
      if(emaCrossDown && !shouldExit)
      {
         shouldExit = true;
         exitReason = "EMA8 cassée - Momentum perdu";
      }
      
      // 3. RSI en surachat extrême
      if(rsi >= 75 && !shouldExit)
      {
         shouldExit = true;
         exitReason = "RSI 75+ Take profit!";
      }
      
      // 4. RSI zone neutre HAUTE (65+) + bougie baissière
      if(rsi >= 65 && closePrice < openPrice && !shouldExit)
      {
         shouldExit = true;
         exitReason = "RSI 65 + bougie rouge - Sécurise";
      }
   }
   
   // === SORTIE POSITION SELL ===
   if(g_positionType == SIGNAL_SELL)
   {
      // 1. Bougie de retournement haussière FORTE (engulfing strict)
      bool bullishEngulfing = (closePrice > openPrice) &&  // Bougie haussière
                               (openPrice <= closePricePrev) && // Open <= close précédent
                               (closePrice >= openPricePrev) && // Close >= open précédent
                               (bodySize1 > bodySize2 * 0.8);    // Corps significatif
      if(bullishEngulfing)
      {
         shouldExit = true;
         exitReason = "Engulfing haussier - SORS!";
      }
      
      // 2. Prix croise EMA 8 vers le haut
      bool emaCrossUp = (closePricePrev < emaExitPrev) && (closePrice > emaExit);
      if(emaCrossUp && !shouldExit)
      {
         shouldExit = true;
         exitReason = "EMA8 cassée - Momentum perdu";
      }
      
      // 3. RSI en survente extrême
      if(rsi <= 25 && !shouldExit)
      {
         shouldExit = true;
         exitReason = "RSI 25- Take profit!";
      }
      
      // 4. RSI zone neutre BASSE (35-) + bougie haussière
      if(rsi <= 35 && closePrice > openPrice && !shouldExit)
      {
         shouldExit = true;
         exitReason = "RSI 35 + bougie verte - Sécurise";
      }
   }
   
   if(shouldExit)
   {
      SendExitSignal(exitReason);
   }
}

//+------------------------------------------------------------------+
//| Envoi signal d'ENTRÉE                                            |
//+------------------------------------------------------------------+
void SendEntrySignal(SIGNAL_TYPE signal)
{
   g_lastSignal = signal;
   g_inPosition = true;
   g_positionType = signal;
   
   string direction = (signal == SIGNAL_BUY) ? "BUY 🟢" : "SELL 🔴";
   string emoji = (signal == SIGNAL_BUY) ? "🚀" : "💣";
   
   string msg = emoji + " SWIFT REAPER " + emoji + "\n" +
                "━━━━━━━━━━━━━━━\n" +
                "📍 " + g_displayName + "\n" +
                "🎯 ENTRE " + direction + " MAINTENANT!\n" +
                "━━━━━━━━━━━━━━━\n" +
                "⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
   
   Print(msg);
   
   if(EnableAlerts)
      Alert(msg);
   
   if(EnableNotifications)
      SendNotification(msg);
}

//+------------------------------------------------------------------+
//| Envoi signal de SORTIE                                           |
//+------------------------------------------------------------------+
void SendExitSignal(string reason)
{
   string direction = (g_positionType == SIGNAL_BUY) ? "BUY" : "SELL";
   
   string msg = "🛑 SWIFT REAPER 🛑\n" +
                "━━━━━━━━━━━━━━━\n" +
                "📍 " + g_displayName + "\n" +
                "📤 SORS DU " + direction + " MAINTENANT!\n" +
                "📊 Raison: " + reason + "\n" +
                "━━━━━━━━━━━━━━━\n" +
                "⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
   
   Print(msg);
   
   if(EnableAlerts)
      Alert(msg);
   
   if(EnableNotifications)
      SendNotification(msg);
   
   // Reset état
   g_inPosition = false;
   g_positionType = SIGNAL_NONE;
   g_lastSignal = SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Vérification heures autorisées (Bénin GMT+1)                     |
//+------------------------------------------------------------------+
bool IsTimeAllowed()
{
   // Utiliser le GMT détecté automatiquement ou celui défini par l'utilisateur
   int brokerGMT = (BrokerGMTOffset != 0) ? BrokerGMTOffset : g_detectedBrokerGMT;
   
   // Convertir heure broker en heure Bénin (GMT+1)
   // Heure Bénin = Heure Broker - BrokerGMT + 1
   int currentHour = Hour() - brokerGMT + 1;
   if(currentHour < 0) currentHour += 24;
   if(currentHour >= 24) currentHour -= 24;
   
   int dayOfWeek = DayOfWeek();
   
   // Weekend - pas de trading
   if(dayOfWeek == 0 || dayOfWeek == 6)
      return false;
   
   // Lundi avant 10h
   if(FilterMonday && dayOfWeek == 1 && currentHour < 10)
   {
      return false;
   }
   
   // Vendredi après 18h
   if(FilterFriday && dayOfWeek == 5 && currentHour >= 18)
   {
      return false;
   }
   
   // Heures de trading normales
   if(currentHour < StartHour || currentHour >= EndHour)
   {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Vérification news HIGH IMPACT (MT4 - Manuel)                     |
//+------------------------------------------------------------------+
bool IsHighImpactNewsNear()
{
   if(!FilterHighImpactNews)
      return false;
   
   // MT4 n'a pas de calendrier économique intégré
   // On utilise les heures configurées manuellement
   
   int currentHour = Hour();
   int currentMinute = Minute();
   int currentTimeInt = currentHour * 100 + currentMinute;
   
   // Vérifier chaque heure de news configurée
   if(CheckNewsTime(NewsTime1, currentTimeInt)) return true;
   if(CheckNewsTime(NewsTime2, currentTimeInt)) return true;
   if(CheckNewsTime(NewsTime3, currentTimeInt)) return true;
   if(CheckNewsTime(NewsTime4, currentTimeInt)) return true;
   if(CheckNewsTime(NewsTime5, currentTimeInt)) return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Vérification proximité d'une heure de news                       |
//+------------------------------------------------------------------+
bool CheckNewsTime(string newsTimeStr, int currentTimeInt)
{
   if(StringLen(newsTimeStr) != 4) return false;
   
   int newsTime = (int)StringToInteger(newsTimeStr);
   if(newsTime == 0) return false;
   
   // Convertir en minutes pour faciliter le calcul
   int newsHour = newsTime / 100;
   int newsMinute = newsTime % 100;
   int newsMinutes = newsHour * 60 + newsMinute;
   
   int currentHour = currentTimeInt / 100;
   int currentMinute = currentTimeInt % 100;
   int currentMinutes = currentHour * 60 + currentMinute;
   
   // Vérifier si on est dans la fenêtre avant/après
   int diff = MathAbs(currentMinutes - newsMinutes);
   
   if(diff <= NewsMinutesBefore || diff <= NewsMinutesAfter)
   {
      Print("⚠️ Proche d'une news configurée: ", newsTimeStr);
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Création panneau d'affichage                                     |
//+------------------------------------------------------------------+
void CreatePanel()
{
   int x = 10;
   int y = 30;
   
   // Titre
   CreateLabel(g_panelName + "_title", "☠️ SWIFT REAPER v2.0 (MT4)", x, y, clrWhite, 12);
   y += 25;
   
   // Symbole
   CreateLabel(g_panelName + "_symbol", g_displayName, x, y, clrGold, 14);
   y += 25;
   
   // Tendance
   CreateLabel(g_panelName + "_trend", "Tendance: ---", x, y, clrWhite, 10);
   y += 20;
   
   // État
   CreateLabel(g_panelName + "_state", "État: En attente", x, y, clrWhite, 10);
   y += 20;
   
   // Filtre horaire
   CreateLabel(g_panelName + "_time", "Heures: ---", x, y, clrWhite, 10);
   y += 20;
   
   // Filtre news
   CreateLabel(g_panelName + "_news", "News: ---", x, y, clrWhite, 10);
}

//+------------------------------------------------------------------+
//| Création label                                                   |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int fontSize)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Mise à jour panneau                                              |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   // Tendance
   string trendText = "Tendance: ";
   color trendColor = clrGray;
   
   switch(g_currentTrend)
   {
      case TREND_BULLISH:
         trendText += "HAUSSIÈRE ▲";
         trendColor = clrLime;
         break;
      case TREND_BEARISH:
         trendText += "BAISSIÈRE ▼";
         trendColor = clrRed;
         break;
      default:
         trendText += "NEUTRE ●";
         trendColor = clrGray;
   }
   
   ObjectSetString(0, g_panelName + "_trend", OBJPROP_TEXT, trendText);
   ObjectSetInteger(0, g_panelName + "_trend", OBJPROP_COLOR, trendColor);
   
   // État
   string stateText = "État: ";
   color stateColor = clrWhite;
   
   if(g_inPosition)
   {
      stateText += (g_positionType == SIGNAL_BUY) ? "EN POSITION BUY 🟢" : "EN POSITION SELL 🔴";
      stateColor = (g_positionType == SIGNAL_BUY) ? clrLime : clrRed;
   }
   else
   {
      stateText += "En attente de signal ⏳";
      stateColor = clrYellow;
   }
   
   ObjectSetString(0, g_panelName + "_state", OBJPROP_TEXT, stateText);
   ObjectSetInteger(0, g_panelName + "_state", OBJPROP_COLOR, stateColor);
   
   // Filtre horaire
   string timeText = "Heures: ";
   color timeColor = clrWhite;
   
   if(IsTimeAllowed())
   {
      timeText += "ACTIF ✅";
      timeColor = clrLime;
   }
   else
   {
      timeText += "INACTIF ❌";
      timeColor = clrRed;
   }
   
   ObjectSetString(0, g_panelName + "_time", OBJPROP_TEXT, timeText);
   ObjectSetInteger(0, g_panelName + "_time", OBJPROP_COLOR, timeColor);
   
   // Filtre news
   string newsText = "News: ";
   color newsColor = clrWhite;
   
   if(!FilterHighImpactNews)
   {
      newsText += "Filtre désactivé";
      newsColor = clrGray;
   }
   else if(IsHighImpactNewsNear())
   {
      newsText += "⚠️ NEWS PROCHE - NO TRADE";
      newsColor = clrOrange;
   }
   else
   {
      newsText += "OK ✅";
      newsColor = clrLime;
   }
   
   ObjectSetString(0, g_panelName + "_news", OBJPROP_TEXT, newsText);
   ObjectSetInteger(0, g_panelName + "_news", OBJPROP_COLOR, newsColor);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Détection automatique du GMT du broker                           |
//+------------------------------------------------------------------+
int DetectBrokerGMTOffset()
{
   // Si l'utilisateur a défini manuellement, utiliser sa valeur
   if(BrokerGMTOffset != 0)
      return BrokerGMTOffset;
   
   // Pour MT4, on utilise TimeGMT() et TimeCurrent()
   datetime brokerTime = TimeCurrent();
   datetime gmtTime = TimeGMT();
   
   // Différence en secondes
   int diffSeconds = (int)(brokerTime - gmtTime);
   
   // Convertir en heures
   int diffHours = diffSeconds / 3600;
   
   return diffHours;
}

//+------------------------------------------------------------------+
//| Sauvegarder l'état dans un fichier                               |
//+------------------------------------------------------------------+
void SaveState()
{
   int fileHandle = FileOpen(g_stateFileName, FILE_WRITE|FILE_TXT);
   
   if(fileHandle != INVALID_HANDLE)
   {
      // Format: inPosition|positionType|trend
      string stateData = IntegerToString(g_inPosition ? 1 : 0) + "|" +
                         IntegerToString((int)g_positionType) + "|" +
                         IntegerToString((int)g_currentTrend);
      
      FileWriteString(fileHandle, stateData);
      FileClose(fileHandle);
      
      Print("💾 État sauvegardé: ", stateData);
   }
   else
   {
      Print("⚠️ Impossible de sauvegarder l'état");
   }
}

//+------------------------------------------------------------------+
//| Charger l'état depuis un fichier                                 |
//+------------------------------------------------------------------+
void LoadState()
{
   if(!FileIsExist(g_stateFileName))
   {
      Print("📄 Pas d'état précédent trouvé - Démarrage frais");
      return;
   }
   
   int fileHandle = FileOpen(g_stateFileName, FILE_READ|FILE_TXT);
   
   if(fileHandle != INVALID_HANDLE)
   {
      string stateData = FileReadString(fileHandle);
      FileClose(fileHandle);
      
      // Parser les données: inPosition|positionType|trend
      string parts[];
      int count = StringSplit(stateData, '|', parts);
      
      if(count >= 3)
      {
         g_inPosition = (StrToInteger(parts[0]) == 1);
         g_positionType = (SIGNAL_TYPE)StrToInteger(parts[1]);
         g_currentTrend = (TREND_TYPE)StrToInteger(parts[2]);
         
         Print("📂 État chargé: Position=", g_inPosition, 
               ", Type=", EnumToString(g_positionType),
               ", Tendance=", EnumToString(g_currentTrend));
      }
      else
      {
         Print("⚠️ Fichier d'état corrompu - Démarrage frais");
      }
   }
}

//+------------------------------------------------------------------+
//| Réinitialiser l'état (si besoin manuel)                          |
//+------------------------------------------------------------------+
void ResetState()
{
   g_inPosition = false;
   g_positionType = SIGNAL_NONE;
   g_lastSignal = SIGNAL_NONE;
   
   // Supprimer le fichier d'état
   if(FileIsExist(g_stateFileName))
      FileDelete(g_stateFileName);
   
   Print("🔄 État réinitialisé");
}
//+------------------------------------------------------------------+
