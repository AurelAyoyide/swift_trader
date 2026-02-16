//+------------------------------------------------------------------+
//|                                              SwiftReaper.mq5     |
//|                        Copyright 2026, SwiftReaper Development   |
//|                                    https://www.swiftreaper.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, SwiftReaper Development"
#property link      "https://www.swiftreaper.com"
#property version   "2.10"
#property description "SwiftReaper v2.1 - Le Faucheur de Pips"
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
input group "=== NOTIFICATIONS ==="
input bool     EnableNotifications = true;       // Activer les notifications push
input bool     EnableAlerts = true;              // Activer les alertes sonores

// Timeframes
input group "=== TIMEFRAMES ==="
input ENUM_TIMEFRAMES TF_Trend = PERIOD_H1;      // Timeframe tendance (H1)
input ENUM_TIMEFRAMES TF_Entry = PERIOD_M5;      // Timeframe entrée (M5)

// Indicateurs
input group "=== INDICATEURS ==="
input int      EMA_Period = 50;                  // Période EMA (tendance H1)
input int      RSI_Period = 14;                  // Période RSI (entrée M5)
input int      RSI_Oversold = 30;                // RSI survente (BUY zone)
input int      RSI_Overbought = 70;              // RSI surachat (SELL zone)
input int      EMA_Exit_Period = 8;              // EMA rapide pour sortie M5

// Filtres horaires (Heure du Bénin GMT+1)
input group "=== FILTRES HORAIRES (Bénin GMT+1) ==="
input int      BrokerGMTOffset = 0;              // Décalage GMT du broker (0 si GMT, 2 si GMT+2, etc.)
input int      StartHour = 8;                    // Heure début (08h00 Bénin)
input int      EndHour = 21;                     // Heure fin (21h00 Bénin)
input bool     FilterMonday = true;              // Éviter lundi avant 10h
input bool     FilterFriday = true;              // Éviter vendredi après 18h

// Filtre News
input group "=== FILTRE NEWS ==="
input bool     FilterHighImpactNews = true;      // Filtrer les news HIGH IMPACT
input int      NewsMinutesBefore = 30;           // Minutes avant news (pas de signal)
input int      NewsMinutesAfter = 30;            // Minutes après news (pas de signal)

// Paires (pour multi-chart)
input group "=== IDENTIFICATION ==="
input string   PairName = "";                    // Nom personnalisé (vide = auto)

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

// Handles indicateurs
int g_emaH1Handle;
int g_rsiM5Handle;
int g_emaExitM5Handle;

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
   
   // Création des handles indicateurs
   g_emaH1Handle = iMA(g_symbol, TF_Trend, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   g_rsiM5Handle = iRSI(g_symbol, TF_Entry, RSI_Period, PRICE_CLOSE);
   g_emaExitM5Handle = iMA(g_symbol, TF_Entry, EMA_Exit_Period, 0, MODE_EMA, PRICE_CLOSE);
   
   // Vérification handles
   if(g_emaH1Handle == INVALID_HANDLE || g_rsiM5Handle == INVALID_HANDLE || g_emaExitM5Handle == INVALID_HANDLE)
   {
      Print("❌ Erreur création indicateurs");
      return INIT_FAILED;
   }
   
   // Charger l'état sauvegardé (si existe)
   LoadState();
   
   // Création panneau
   CreatePanel();
   
   // Timer pour vérification périodique
   EventSetTimer(1);
   
   // Détection tendance initiale
   DetectTrend();
   
   Print("✅ SwiftReaper v2.1 initialisé sur ", g_displayName);
   Print("📍 Mode: Notifications uniquement");
   Print("⏰ Heures actives: ", StartHour, "h - ", EndHour, "h (Bénin)");
   if(g_inPosition)
      Print("🔄 État restauré: EN POSITION ", (g_positionType == SIGNAL_BUY ? "BUY" : "SELL"));
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Sauvegarder l'état avant de fermer
   SaveState();
   
   // Libération handles
   if(g_emaH1Handle != INVALID_HANDLE) IndicatorRelease(g_emaH1Handle);
   if(g_rsiM5Handle != INVALID_HANDLE) IndicatorRelease(g_rsiM5Handle);
   if(g_emaExitM5Handle != INVALID_HANDLE) IndicatorRelease(g_emaExitM5Handle);
   
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
   datetime h1Time[], m5Time[];
   ArraySetAsSeries(h1Time, true);
   ArraySetAsSeries(m5Time, true);
   
   // Récupération temps des bougies
   if(CopyTime(g_symbol, TF_Trend, 0, 2, h1Time) < 2) return;
   if(CopyTime(g_symbol, TF_Entry, 0, 2, m5Time) < 2) return;
   
   // Nouvelle bougie H1 FERMÉE
   if(h1Time[1] > g_lastH1Candle && g_lastH1Candle != 0)
   {
      DetectTrend();
   }
   g_lastH1Candle = h1Time[1];
   
   // Nouvelle bougie M5 FERMÉE
   if(m5Time[1] > g_lastM5Candle && g_lastM5Candle != 0)
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
   g_lastM5Candle = m5Time[1];
}

//+------------------------------------------------------------------+
//| Détection tendance H1 (sur bougies FERMÉES)                      |
//+------------------------------------------------------------------+
void DetectTrend()
{
   double emaValues[];
   double closePrice[];
   
   ArraySetAsSeries(emaValues, true);
   ArraySetAsSeries(closePrice, true);
   
   // Copie EMA et prix de clôture (bougie fermée = index 1)
   if(CopyBuffer(g_emaH1Handle, 0, 0, 3, emaValues) < 3) return;
   if(CopyClose(g_symbol, TF_Trend, 0, 3, closePrice) < 3) return;
   
   // Analyse sur bougie FERMÉE (index 1)
   TREND_TYPE previousTrend = g_currentTrend;
   
   if(closePrice[1] > emaValues[1])
      g_currentTrend = TREND_BULLISH;
   else if(closePrice[1] < emaValues[1])
      g_currentTrend = TREND_BEARISH;
   else
      g_currentTrend = TREND_NONE;
   
   // Notification si changement de tendance
   if(previousTrend != g_currentTrend && previousTrend != TREND_NONE)
   {
      string trendText = (g_currentTrend == TREND_BULLISH) ? "HAUSSIÈRE 📈" : "BAISSIÈRE 📉";
      string msg = "🔄 SWIFT REAPER\n" +
                   g_displayName + "\n" +
                   "Tendance: " + trendText;
      
      Print(msg);
      // Pas de notification push pour changement de tendance (trop fréquent)
   }
}

//+------------------------------------------------------------------+
//| Vérification signal d'ENTRÉE (M5 bougie FERMÉE)                  |
//+------------------------------------------------------------------+
void CheckEntrySignal()
{
   if(g_currentTrend == TREND_NONE) return;
   
   double rsiValues[];
   double closePrice[];
   double openPrice[];
   double highPrice[];
   double lowPrice[];
   
   ArraySetAsSeries(rsiValues, true);
   ArraySetAsSeries(closePrice, true);
   ArraySetAsSeries(openPrice, true);
   ArraySetAsSeries(highPrice, true);
   ArraySetAsSeries(lowPrice, true);
   
   // Récupération données (bougie fermée = index 1)
   if(CopyBuffer(g_rsiM5Handle, 0, 0, 3, rsiValues) < 3) return;
   if(CopyClose(g_symbol, TF_Entry, 0, 3, closePrice) < 3) return;
   if(CopyOpen(g_symbol, TF_Entry, 0, 3, openPrice) < 3) return;
   if(CopyHigh(g_symbol, TF_Entry, 0, 3, highPrice) < 3) return;
   if(CopyLow(g_symbol, TF_Entry, 0, 3, lowPrice) < 3) return;
   
   // RSI sur bougie fermée
   double rsi = rsiValues[1];
   double rsiPrev = rsiValues[2];
   
   // Vérification bougie de confirmation (bougie fermée)
   bool bullishCandle = closePrice[1] > openPrice[1];
   bool bearishCandle = closePrice[1] < openPrice[1];
   
   // Pin bar / bougie de rejet
   double bodySize = MathAbs(closePrice[1] - openPrice[1]);
   double upperWick = highPrice[1] - MathMax(closePrice[1], openPrice[1]);
   double lowerWick = MathMin(closePrice[1], openPrice[1]) - lowPrice[1];
   
   bool bullishRejection = (lowerWick > bodySize * 1.5) && bullishCandle;
   bool bearishRejection = (upperWick > bodySize * 1.5) && bearishCandle;
   
   // === SIGNAL BUY ===
   // Tendance haussière + RSI était survendu + bougie haussière de confirmation
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
   // Tendance baissière + RSI était suracheté + bougie baissière de confirmation
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
   double rsiValues[];
   double emaExitValues[];
   double closePrice[];
   double openPrice[];
   double highPrice[];
   double lowPrice[];
   
   ArraySetAsSeries(rsiValues, true);
   ArraySetAsSeries(emaExitValues, true);
   ArraySetAsSeries(closePrice, true);
   ArraySetAsSeries(openPrice, true);
   ArraySetAsSeries(highPrice, true);
   ArraySetAsSeries(lowPrice, true);
   
   // Récupération données
   if(CopyBuffer(g_rsiM5Handle, 0, 0, 3, rsiValues) < 3) return;
   if(CopyBuffer(g_emaExitM5Handle, 0, 0, 3, emaExitValues) < 3) return;
   if(CopyClose(g_symbol, TF_Entry, 0, 3, closePrice) < 3) return;
   if(CopyOpen(g_symbol, TF_Entry, 0, 3, openPrice) < 3) return;
   if(CopyHigh(g_symbol, TF_Entry, 0, 3, highPrice) < 3) return;
   if(CopyLow(g_symbol, TF_Entry, 0, 3, lowPrice) < 3) return;
   
   double rsi = rsiValues[1];
   bool shouldExit = false;
   string exitReason = "";
   
   // Calcul taille des bougies pour engulfing strict
   double bodySize1 = MathAbs(closePrice[1] - openPrice[1]);
   double bodySize2 = MathAbs(closePrice[2] - openPrice[2]);
   
   // === SORTIE POSITION BUY ===
   if(g_positionType == SIGNAL_BUY)
   {
      // 1. Bougie de retournement baissière FORTE (engulfing strict)
      // Le corps actuel doit être plus grand ET englober complètement le précédent
      bool bearishEngulfing = (closePrice[1] < openPrice[1]) &&  // Bougie baissière
                               (openPrice[1] >= closePrice[2]) && // Open >= close précédent
                               (closePrice[1] <= openPrice[2]) && // Close <= open précédent  
                               (bodySize1 > bodySize2 * 0.8);    // Corps significatif
      if(bearishEngulfing)
      {
         shouldExit = true;
         exitReason = "Engulfing baissier - SORS!";
      }
      
      // 2. Prix croise EMA 8 vers le bas (sur clôture) - Signal d'affaiblissement
      bool emaCrossDown = (closePrice[2] > emaExitValues[2]) && (closePrice[1] < emaExitValues[1]);
      if(emaCrossDown && !shouldExit)
      {
         shouldExit = true;
         exitReason = "EMA8 cassée - Momentum perdu";
      }
      
      // 3. RSI en surachat extrême (prendre profit - le marché a donné)
      if(rsi >= 75 && !shouldExit)
      {
         shouldExit = true;
         exitReason = "RSI 75+ Take profit!";
      }
      
      // 4. RSI zone neutre HAUTE (65+) = on a bien profité, on peut sortir
      // SEULEMENT si combiné avec une bougie baissière
      if(rsi >= 65 && closePrice[1] < openPrice[1] && !shouldExit)
      {
         shouldExit = true;
         exitReason = "RSI 65 + bougie rouge - Sécurise";
      }
   }
   
   // === SORTIE POSITION SELL ===
   if(g_positionType == SIGNAL_SELL)
   {
      // 1. Bougie de retournement haussière FORTE (engulfing strict)
      bool bullishEngulfing = (closePrice[1] > openPrice[1]) &&  // Bougie haussière
                               (openPrice[1] <= closePrice[2]) && // Open <= close précédent
                               (closePrice[1] >= openPrice[2]) && // Close >= open précédent
                               (bodySize1 > bodySize2 * 0.8);    // Corps significatif
      if(bullishEngulfing)
      {
         shouldExit = true;
         exitReason = "Engulfing haussier - SORS!";
      }
      
      // 2. Prix croise EMA 8 vers le haut (sur clôture)
      bool emaCrossUp = (closePrice[2] < emaExitValues[2]) && (closePrice[1] > emaExitValues[1]);
      if(emaCrossUp && !shouldExit)
      {
         shouldExit = true;
         exitReason = "EMA8 cassée - Momentum perdu";
      }
      
      // 3. RSI en survente extrême (prendre profit)
      if(rsi <= 25 && !shouldExit)
      {
         shouldExit = true;
         exitReason = "RSI 25- Take profit!";
      }
      
      // 4. RSI zone neutre BASSE (35-) = on a bien profité
      // SEULEMENT si combiné avec une bougie haussière
      if(rsi <= 35 && closePrice[1] > openPrice[1] && !shouldExit)
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
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // Utiliser le GMT détecté automatiquement ou celui défini par l'utilisateur
   int brokerGMT = (BrokerGMTOffset != 0) ? BrokerGMTOffset : g_detectedBrokerGMT;
   
   // Convertir heure broker en heure Bénin (GMT+1)
   // Heure Bénin = Heure Broker - BrokerGMT + 1
   int currentHour = dt.hour - brokerGMT + 1;
   if(currentHour < 0) currentHour += 24;
   if(currentHour >= 24) currentHour -= 24;
   
   int dayOfWeek = dt.day_of_week;
   
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
//| Vérification news HIGH IMPACT proches (MT5 natif)                |
//+------------------------------------------------------------------+
bool IsHighImpactNewsNear()
{
   if(!FilterHighImpactNews)
      return false;
   
   datetime currentTime = TimeCurrent();
   datetime startTime = currentTime - NewsMinutesAfter * 60;  // Passé
   datetime endTime = currentTime + NewsMinutesBefore * 60;   // Futur
   
   // Récupération des événements économiques
   MqlCalendarValue values[];
   
   // Récupérer les événements dans la fenêtre de temps
   int count = CalendarValueHistory(values, startTime, endTime);
   
   if(count <= 0)
      return false;
   
   // Parcourir les événements
   for(int i = 0; i < count; i++)
   {
      MqlCalendarEvent event;
      
      if(CalendarEventById(values[i].event_id, event))
      {
         // Vérifier si c'est HIGH IMPACT
         if(event.importance == CALENDAR_IMPORTANCE_HIGH)
         {
            // Vérifier si ça concerne notre paire
            MqlCalendarCountry country;
            if(CalendarCountryById(event.country_id, country))
            {
               string currency = country.currency;
               
               // Vérifier si la devise est dans notre paire
               if(StringFind(g_symbol, currency) >= 0)
               {
                  Print("⚠️ News HIGH IMPACT proche: ", event.name, " (", currency, ")");
                  return true;
               }
            }
         }
      }
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
   CreateLabel(g_panelName + "_title", "☠️ SWIFT REAPER v2.1", x, y, clrBlack, 12);
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
   
   // Sinon, calculer automatiquement
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
         g_inPosition = (StringToInteger(parts[0]) == 1);
         g_positionType = (SIGNAL_TYPE)StringToInteger(parts[1]);
         g_currentTrend = (TREND_TYPE)StringToInteger(parts[2]);
         
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
