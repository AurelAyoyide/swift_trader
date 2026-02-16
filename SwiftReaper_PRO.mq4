//+------------------------------------------------------------------+
//|                                          SwiftReaper_PRO.mq4     |
//|                        Copyright 2026, SwiftReaper Development   |
//|                                    https://www.swiftreaper.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, SwiftReaper Development"
#property link      "https://www.swiftreaper.com"
#property version   "3.20"
#property description "SwiftReaper PRO v3.2 (MT4) - Le Faucheur Ultime"
#property description "Fusion SwiftReaper + SwiftTrader + Filtres Expert"
#property description "Sorties H24 - Anti-doji - Mode Full Margin"
#property strict

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum TREND_TYPE
{
   TREND_NONE,
   TREND_BULLISH,
   TREND_BEARISH,
   TREND_RANGE
};

enum SIGNAL_TYPE
{
   SIGNAL_NONE,
   SIGNAL_BUY,
   SIGNAL_SELL,
   SIGNAL_EXIT_BUY,
   SIGNAL_EXIT_SELL
};

enum SIGNAL_CONFIDENCE
{
   CONFIDENCE_NONE,
   CONFIDENCE_MODERATE,
   CONFIDENCE_HIGH
};

//+------------------------------------------------------------------+
//| PARAMÈTRES D'ENTRÉE                                              |
//+------------------------------------------------------------------+
// Notifications
extern bool     EnableNotifications = true;       // Activer les notifications push
extern bool     EnableAlerts = true;              // Activer les alertes sonores
extern bool     HighConfidenceOnly = false;       // ONLY signaux HIGH (full margin)
extern color    PanelColor = clrBlack;            // Couleur texte du panneau

// Timeframes
extern ENUM_TIMEFRAMES TF_Trend = PERIOD_H1;      // Timeframe tendance (H1)
extern ENUM_TIMEFRAMES TF_Entry = PERIOD_M5;      // Timeframe entrée (M5)

// Indicateurs Tendance (H1)
extern int      EMA_Period = 50;                  // Période EMA (tendance H1)
extern int      ADX_Period = 14;                  // Période ADX (force tendance)
extern double   ADX_Threshold = 20.0;             // Seuil ADX minimum (< = RANGE)
extern double   ADX_Strong = 30.0;                // ADX fort (confiance HIGH)

// Indicateurs Entrée (M5)
extern int      RSI_Period = 14;                  // Période RSI (entrée M5)
extern int      RSI_Oversold = 35;                // RSI survente (BUY zone) - élargi pour + de signaux
extern int      RSI_Overbought = 65;              // RSI surachat (SELL zone) - élargi pour + de signaux
extern int      EMA_Exit_Period = 13;             // EMA sortie M5 (13 = laisse respirer)
extern int      RSI_Exit_TakeProfit = 75;         // RSI take profit (surachat extrême)
extern int      RSI_Exit_Secure = 70;             // RSI sécurisation (+ bougie opposée)

// Filtres Avancés
extern int      ATR_Period = 14;                  // Période ATR (volatilité)
extern double   ATR_Min_Multiplier = 0.3;         // ATR min vs moyenne (30%)
extern int      MaxSpreadPoints = 30;             // Spread max autorisé (points)
extern int      SignalCooldownMinutes = 10;        // Cooldown entre signaux (min)

// Filtres horaires (Bénin GMT+1)
extern int      BrokerGMTOffset = 0;              // Décalage GMT broker (0=auto, 2=XM)
extern int      StartHour = 8;                    // Heure début (08h00 Bénin)
extern int      EndHour = 21;                     // Heure fin (21h00 Bénin)
extern bool     FilterMonday = true;              // Éviter lundi avant 10h
extern bool     FilterFriday = true;              // Éviter vendredi après 18h

// Filtre News (MT4: manuel)
extern bool     FilterHighImpactNews = false;     // Filtrer news (config manuelle)
extern int      NewsMinutesBefore = 30;           // Minutes avant news
extern int      NewsMinutesAfter = 30;            // Minutes après news
extern string   NewsTime1 = "";                   // News 1 (ex: "1430")
extern string   NewsTime2 = "";                   // News 2
extern string   NewsTime3 = "";                   // News 3
extern string   NewsTime4 = "";                   // News 4
extern string   NewsTime5 = "";                   // News 5

// Identification
extern string   PairName = "";                    // Nom personnalisé (vide = auto)

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                               |
//+------------------------------------------------------------------+
TREND_TYPE g_currentTrend = TREND_NONE;
SIGNAL_TYPE g_lastSignal = SIGNAL_NONE;
SIGNAL_CONFIDENCE g_lastConfidence = CONFIDENCE_NONE;
bool g_inPosition = false;
SIGNAL_TYPE g_positionType = SIGNAL_NONE;

// Données pour panneau
double g_currentADX = 0;
double g_currentDIPlus = 0;
double g_currentDIMinus = 0;
double g_currentATR = 0;
double g_averageATR = 0;
double g_currentRSI = 0;
double g_currentSpread = 0;

string g_symbol;
string g_displayName;

datetime g_lastH1Candle = 0;
datetime g_lastM5Candle = 0;
datetime g_lastSignalTime = 0;

// Compteur de clôtures sous/dessus EMA exit (exige 2 clôtures)
int g_emaCrossCount = 0;

// Protection breakeven
bool g_breakevenNotified = false;

string g_panelName = "SwiftReaperPRO";
string g_stateFileName;
int g_detectedBrokerGMT = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol = Symbol();
   g_displayName = (PairName != "") ? PairName : g_symbol;
   g_stateFileName = "SwiftReaperPRO_" + g_symbol + "_state.txt";
   
   g_detectedBrokerGMT = DetectBrokerGMTOffset();
   Print("🌍 GMT Broker détecté: GMT+", g_detectedBrokerGMT);
   
   LoadState();
   CreatePanel();
   EventSetTimer(1);
   DetectTrend();
   
   Print("✅ SwiftReaper PRO v3.2 (MT4) initialisé sur ", g_displayName);
   if(HighConfidenceOnly)
      Print("⭐ MODE: HIGH CONFIDENCE ONLY (full margin)");
   Print("📍 Mode: Notifications uniquement");
   Print("⏰ Heures actives: ", StartHour, "h - ", EndHour, "h (Bénin)");
   Print("📊 ADX Seuil: ", ADX_Threshold, " | Spread Max: ", MaxSpreadPoints, " pts");
   
   if(g_inPosition)
      Print("🔄 État restauré: EN POSITION ", (g_positionType == SIGNAL_BUY ? "BUY" : "SELL"));
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   SaveState();
   ObjectsDeleteAll(0, g_panelName);
   EventKillTimer();
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   g_currentSpread = MarketInfo(g_symbol, MODE_SPREAD);
   CheckNewCandles();
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
   datetime h1Time = iTime(g_symbol, TF_Trend, 1);
   datetime m5Time = iTime(g_symbol, TF_Entry, 1);
   
   // Nouvelle bougie H1 FERMÉE
   if(h1Time > g_lastH1Candle && g_lastH1Candle != 0)
   {
      TREND_TYPE previousTrend = g_currentTrend;
      DetectTrend();
      
      // Sortie si tendance se retourne contre nous
      if(g_inPosition)
      {
         if(g_positionType == SIGNAL_BUY && (g_currentTrend == TREND_BEARISH || g_currentTrend == TREND_RANGE))
            SendExitSignal("⚠️ TENDANCE H1 retournée - Sors!");
         else if(g_positionType == SIGNAL_SELL && (g_currentTrend == TREND_BULLISH || g_currentTrend == TREND_RANGE))
            SendExitSignal("⚠️ TENDANCE H1 retournée - Sors!");
      }
   }
   g_lastH1Candle = h1Time;
   
   // Nouvelle bougie M5 FERMÉE
   if(m5Time > g_lastM5Candle && g_lastM5Candle != 0)
   {
      // SORTIES : toujours vérifiées H24 (jamais bloquées par heure/news)
      if(g_inPosition)
      {
         CheckExitSignal();
      }
      else
      {
         // ENTRÉES : filtrées par heure et news
         if(IsTimeAllowed() && !IsHighImpactNewsNear())
            CheckEntrySignal();
      }
   }
   g_lastM5Candle = m5Time;
}

//+------------------------------------------------------------------+
//| Détection tendance H1 (EMA50 + ADX + DI+/DI-)                   |
//+------------------------------------------------------------------+
void DetectTrend()
{
   // EMA 50 (bougie fermée = index 1)
   double ema = iMA(g_symbol, TF_Trend, EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   double closePrice = iClose(g_symbol, TF_Trend, 1);
   
   // ADX + DI
   g_currentADX = iADX(g_symbol, TF_Trend, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
   g_currentDIPlus = iADX(g_symbol, TF_Trend, ADX_Period, PRICE_CLOSE, MODE_PLUSDI, 1);
   g_currentDIMinus = iADX(g_symbol, TF_Trend, ADX_Period, PRICE_CLOSE, MODE_MINUSDI, 1);
   
   // ATR
   g_currentATR = iATR(g_symbol, TF_Trend, ATR_Period, 1);
   
   // ATR moyen (50 bougies)
   double atrSum = 0;
   for(int i = 1; i <= 50; i++)
      atrSum += iATR(g_symbol, TF_Trend, ATR_Period, i);
   g_averageATR = atrSum / 50.0;
   
   // === LOGIQUE DE TENDANCE (3 couches) ===
   TREND_TYPE previousTrend = g_currentTrend;
   
   bool priceAboveEMA = closePrice > ema;
   bool priceBelowEMA = closePrice < ema;
   bool trendExists = g_currentADX >= ADX_Threshold;
   bool diConfirmsBull = g_currentDIPlus > g_currentDIMinus;
   bool diConfirmsBear = g_currentDIMinus > g_currentDIPlus;
   
   if(!trendExists)
   {
      g_currentTrend = TREND_RANGE;
   }
   else if(priceAboveEMA)
   {
      // Prix au-dessus EMA50 = HAUSSIÈRE
      // DI confirme ou pas = on laisse entrer (le pullback cause un DI- temporaire)
      g_currentTrend = TREND_BULLISH;
   }
   else if(priceBelowEMA)
   {
      g_currentTrend = TREND_BEARISH;
   }
   else
   {
      g_currentTrend = TREND_RANGE;
   }
   
   if(previousTrend != g_currentTrend)
   {
      string trendNames[] = {"NEUTRE", "HAUSSIÈRE 📈", "BAISSIÈRE 📉", "RANGE ⏸️"};
      Print("🔄 Tendance: ", trendNames[g_currentTrend], 
            " | ADX: ", DoubleToString(g_currentADX, 1),
            " | DI+: ", DoubleToString(g_currentDIPlus, 1),
            " | DI-: ", DoubleToString(g_currentDIMinus, 1));
      
      // NOUVEAU: Notification quand on SORT du range
      if(previousTrend == TREND_RANGE && (g_currentTrend == TREND_BULLISH || g_currentTrend == TREND_BEARISH))
      {
         string alertMsg = "🔔 SWIFT REAPER PRO\n" +
                          "📍 " + g_displayName + "\n" +
                          "💡 SORTIE DE RANGE!\n" +
                          "Nouvelle tendance: " + trendNames[g_currentTrend] + "\n" +
                          "ADX: " + DoubleToString(g_currentADX, 1) + "\n" +
                          "Prépare-toi, un signal peut arriver!";
         Print(alertMsg);
         if(EnableNotifications)
            SendNotification(alertMsg);
      }
   }
}

//+------------------------------------------------------------------+
//| Vérification signal d'ENTRÉE (M5 bougie FERMÉE)                  |
//+------------------------------------------------------------------+
void CheckEntrySignal()
{
   if(g_currentTrend == TREND_NONE || g_currentTrend == TREND_RANGE) return;
   if(!IsVolatilityOK()) return;
   if(!IsSpreadAcceptable()) return;
   if(!IsCooldownRespected()) return;
   
   double rsi = iRSI(g_symbol, TF_Entry, RSI_Period, PRICE_CLOSE, 1);
   double rsiPrev = iRSI(g_symbol, TF_Entry, RSI_Period, PRICE_CLOSE, 2);
   g_currentRSI = rsi;
   
   double closePrice = iClose(g_symbol, TF_Entry, 1);
   double openPrice = iOpen(g_symbol, TF_Entry, 1);
   double highPrice = iHigh(g_symbol, TF_Entry, 1);
   double lowPrice = iLow(g_symbol, TF_Entry, 1);
   
   bool bullishCandle = closePrice > openPrice;
   bool bearishCandle = closePrice < openPrice;
   
   double bodySize = MathAbs(closePrice - openPrice);
   double upperWick = highPrice - MathMax(closePrice, openPrice);
   double lowerWick = MathMin(closePrice, openPrice) - lowPrice;
   
   bool bullishRejection = (lowerWick > bodySize * 1.5) && bullishCandle;
   bool bearishRejection = (upperWick > bodySize * 1.5) && bearishCandle;
   
   // === SIGNAL BUY ===
   if(g_currentTrend == TREND_BULLISH)
   {
      // RSI sort de survente (élargi: seuil 35 au lieu de 30)
      bool rsiExitOversold = (rsiPrev <= RSI_Oversold && rsi > RSI_Oversold);
      bool rsiWithStrongRejection = (rsi < (RSI_Oversold + 5) && bullishRejection && lowerWick > bodySize * 2.0);
      
      bool rsiCondition = rsiExitOversold || rsiWithStrongRejection;
      
      if(rsiCondition && bullishCandle)
      {
         SIGNAL_CONFIDENCE confidence = CalculateConfidence(SIGNAL_BUY, rsi, rsiPrev, bodySize, lowerWick);
         if(HighConfidenceOnly && confidence != CONFIDENCE_HIGH)
         {
            Print("⏭️ Signal BUY MODERATE ignoré (mode HIGH only)");
            return;
         }
         SendEntrySignal(SIGNAL_BUY, confidence);
         g_emaCrossCount = 0;
         g_breakevenNotified = false;
         return;
      }
   }
   
   // === SIGNAL SELL ===
   if(g_currentTrend == TREND_BEARISH)
   {
      bool rsiExitOverbought = (rsiPrev >= RSI_Overbought && rsi < RSI_Overbought);
      bool rsiWithStrongRejection = (rsi > (RSI_Overbought - 5) && bearishRejection && upperWick > bodySize * 2.0);
      
      bool rsiCondition = rsiExitOverbought || rsiWithStrongRejection;
      
      if(rsiCondition && bearishCandle)
      {
         SIGNAL_CONFIDENCE confidence = CalculateConfidence(SIGNAL_SELL, rsi, rsiPrev, bodySize, upperWick);
         if(HighConfidenceOnly && confidence != CONFIDENCE_HIGH)
         {
            Print("⏭️ Signal SELL MODERATE ignoré (mode HIGH only)");
            return;
         }
         SendEntrySignal(SIGNAL_SELL, confidence);
         g_emaCrossCount = 0;
         g_breakevenNotified = false;
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Vérification signal de SORTIE (M5 bougie FERMÉE)                 |
//+------------------------------------------------------------------+
void CheckExitSignal()
{
   double rsi = iRSI(g_symbol, TF_Entry, RSI_Period, PRICE_CLOSE, 1);
   g_currentRSI = rsi;
   
   double emaExit = iMA(g_symbol, TF_Entry, EMA_Exit_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   double emaExitPrev = iMA(g_symbol, TF_Entry, EMA_Exit_Period, 0, MODE_EMA, PRICE_CLOSE, 2);
   
   double closePrice = iClose(g_symbol, TF_Entry, 1);
   double closePricePrev = iClose(g_symbol, TF_Entry, 2);
   double openPrice = iOpen(g_symbol, TF_Entry, 1);
   double openPricePrev = iOpen(g_symbol, TF_Entry, 2);
   
   bool shouldExit = false;
   string exitReason = "";
   
   double bodySize1 = MathAbs(closePrice - openPrice);
   double bodySize2 = MathAbs(closePricePrev - openPricePrev);
   
   // Protection anti-doji : corps minimum pour engulfing valide
   double pointSize = MarketInfo(g_symbol, MODE_POINT);
   double minBodyForEngulfing = pointSize * 5;
   
   // === PROTECTION BREAKEVEN (notification seulement) ===
   if(!g_breakevenNotified)
   {
      bool breakEvenZone = false;
      if(g_positionType == SIGNAL_BUY && rsi > 50 && rsi < 60)
         breakEvenZone = true;
      if(g_positionType == SIGNAL_SELL && rsi < 50 && rsi > 40)
         breakEvenZone = true;
      
      if(breakEvenZone)
      {
         g_breakevenNotified = true;
         string beMsg = "🛡️ SWIFT REAPER PRO\n" +
                       "📍 " + g_displayName + "\n" +
                       "💡 Trade en profit - pense à sécuriser!\n" +
                       "Mets ton SL à breakeven si possible";
         Print(beMsg);
         if(EnableNotifications)
            SendNotification(beMsg);
      }
   }
   
   // === SORTIE POSITION BUY ===
   if(g_positionType == SIGNAL_BUY)
   {
      // 1. ENGULFING baissier STRICT (corps 1.2x + anti-doji)
      bool bearishEngulfing = (closePrice < openPrice) &&
                               (openPrice >= closePricePrev) &&
                               (closePrice <= openPricePrev) &&
                               (bodySize1 > bodySize2 * 1.2) &&
                               (bodySize2 > minBodyForEngulfing);
      if(bearishEngulfing)
      {
         shouldExit = true;
         exitReason = "Engulfing baissier FORT - SORS!";
      }
      
      // 2. EMA 13 cassée - EXIGE 2 CLÔTURES CONSÉCUTIVES
      bool belowEMA = (closePrice < emaExit);
      if(belowEMA && !shouldExit)
      {
         g_emaCrossCount++;
         if(g_emaCrossCount >= 2)
         {
            shouldExit = true;
            exitReason = "EMA13 cassée x2 - Momentum perdu";
         }
      }
      else if(!belowEMA)
      {
         g_emaCrossCount = 0;
      }
      
      // 3. RSI surachat EXTRÊME (take profit)
      if(rsi >= RSI_Exit_TakeProfit && !shouldExit)
      {
         shouldExit = true;
         exitReason = "RSI " + IntegerToString(RSI_Exit_TakeProfit) + "+ Take profit!";
      }
      
      // 4. RSI sécurisation + bougie rouge FORTE
      bool strongBearishCandle = (closePrice < openPrice) && (bodySize1 > bodySize2 * 0.5);
      if(rsi >= RSI_Exit_Secure && strongBearishCandle && !shouldExit)
      {
         shouldExit = true;
         exitReason = "RSI " + IntegerToString(RSI_Exit_Secure) + " + forte bougie rouge - Sécurise";
      }
   }
   
   // === SORTIE POSITION SELL ===
   if(g_positionType == SIGNAL_SELL)
   {
      // 1. ENGULFING haussier STRICT (+ anti-doji)
      bool bullishEngulfing = (closePrice > openPrice) &&
                               (openPrice <= closePricePrev) &&
                               (closePrice >= openPricePrev) &&
                               (bodySize1 > bodySize2 * 1.2) &&
                               (bodySize2 > minBodyForEngulfing);
      if(bullishEngulfing)
      {
         shouldExit = true;
         exitReason = "Engulfing haussier FORT - SORS!";
      }
      
      // 2. EMA 13 cassée vers le haut - 2 CLÔTURES
      bool aboveEMA = (closePrice > emaExit);
      if(aboveEMA && !shouldExit)
      {
         g_emaCrossCount++;
         if(g_emaCrossCount >= 2)
         {
            shouldExit = true;
            exitReason = "EMA13 cassée x2 - Momentum perdu";
         }
      }
      else if(!aboveEMA)
      {
         g_emaCrossCount = 0;
      }
      
      // 3. RSI survente EXTRÊME (take profit)
      if(rsi <= (100 - RSI_Exit_TakeProfit) && !shouldExit)
      {
         shouldExit = true;
         exitReason = "RSI " + IntegerToString(100 - RSI_Exit_TakeProfit) + "- Take profit!";
      }
      
      // 4. RSI sécurisation + forte bougie verte
      bool strongBullishCandle = (closePrice > openPrice) && (bodySize1 > bodySize2 * 0.5);
      if(rsi <= (100 - RSI_Exit_Secure) && strongBullishCandle && !shouldExit)
      {
         shouldExit = true;
         exitReason = "RSI " + IntegerToString(100 - RSI_Exit_Secure) + " + forte bougie verte - Sécurise";
      }
   }
   
   if(shouldExit)
   {
      g_emaCrossCount = 0;
      g_breakevenNotified = false;
      SendExitSignal(exitReason);
   }
}

//+------------------------------------------------------------------+
//| Calcul niveau de confiance                                       |
//+------------------------------------------------------------------+
SIGNAL_CONFIDENCE CalculateConfidence(SIGNAL_TYPE signal, double rsi, double rsiPrev, double bodySize, double wickSize)
{
   int score = 0;
   
   if(g_currentADX >= ADX_Strong) score += 2;
   else score += 1;
   
   if(signal == SIGNAL_BUY && rsiPrev < 25) score += 2;
   else if(signal == SIGNAL_SELL && rsiPrev > 75) score += 2;
   else if(signal == SIGNAL_BUY && rsiPrev <= RSI_Oversold) score += 1;
   else if(signal == SIGNAL_SELL && rsiPrev >= RSI_Overbought) score += 1;
   
   if(wickSize > bodySize * 2.5) score += 2;
   else if(wickSize > bodySize * 1.5) score += 1;
   
   // DI confirme direction = bonus, sinon 0 (pas pénalisé)
   bool diConfirms = false;
   if(signal == SIGNAL_BUY && g_currentDIPlus > g_currentDIMinus)
      diConfirms = true;
   if(signal == SIGNAL_SELL && g_currentDIMinus > g_currentDIPlus)
      diConfirms = true;
   
   if(diConfirms)
   {
      score += 1;
      double diDiff = MathAbs(g_currentDIPlus - g_currentDIMinus);
      if(diDiff > 10)
         score += 1;
   }
   
   if(g_averageATR > 0 && g_currentATR > g_averageATR * 0.6) score += 1;
   
   return (score >= 5) ? CONFIDENCE_HIGH : CONFIDENCE_MODERATE;
}

//+------------------------------------------------------------------+
//| Envoi signal d'ENTRÉE                                            |
//+------------------------------------------------------------------+
void SendEntrySignal(SIGNAL_TYPE signal, SIGNAL_CONFIDENCE confidence)
{
   g_lastSignal = signal;
   g_lastConfidence = confidence;
   g_inPosition = true;
   g_positionType = signal;
   g_lastSignalTime = TimeCurrent();
   
   SaveState();
   
   string direction = (signal == SIGNAL_BUY) ? "BUY 🟢" : "SELL 🔴";
   string emoji = (signal == SIGNAL_BUY) ? "🚀" : "💣";
   string confText = (confidence == CONFIDENCE_HIGH) ? "⭐ CONFIANCE: FORTE" : "📊 CONFIANCE: MODÉRÉE";
   
   string msg = emoji + " SWIFT REAPER PRO " + emoji + "\n" +
                "━━━━━━━━━━━━━━━━━━\n" +
                "📍 " + g_displayName + "\n" +
                "🎯 ENTRE " + direction + " MAINTENANT!\n" +
                confText + "\n" +
                "━━━━━━━━━━━━━━━━━━\n" +
                "ADX: " + DoubleToString(g_currentADX, 1) +
                " | RSI: " + DoubleToString(g_currentRSI, 1) + "\n" +
                "⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
   
   Print(msg);
   if(EnableAlerts) Alert(msg);
   if(EnableNotifications) SendNotification(msg);
}

//+------------------------------------------------------------------+
//| Envoi signal de SORTIE                                           |
//+------------------------------------------------------------------+
void SendExitSignal(string reason)
{
   string direction = (g_positionType == SIGNAL_BUY) ? "BUY" : "SELL";
   
   string msg = "🛑 SWIFT REAPER PRO 🛑\n" +
                "━━━━━━━━━━━━━━━━━━\n" +
                "📍 " + g_displayName + "\n" +
                "📤 SORS DU " + direction + " MAINTENANT!\n" +
                "📊 Raison: " + reason + "\n" +
                "━━━━━━━━━━━━━━━━━━\n" +
                "⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
   
   Print(msg);
   if(EnableAlerts) Alert(msg);
   if(EnableNotifications) SendNotification(msg);
   
   g_inPosition = false;
   g_positionType = SIGNAL_NONE;
   g_lastSignal = SIGNAL_NONE;
   g_lastConfidence = CONFIDENCE_NONE;
   
   SaveState();
}

//+------------------------------------------------------------------+
//| FILTRE: Spread acceptable                                        |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
   double spread = MarketInfo(g_symbol, MODE_SPREAD);
   if(spread > MaxSpreadPoints)
   {
      Print("⛔ Spread trop élevé: ", DoubleToString(spread, 0), " pts (max: ", MaxSpreadPoints, ")");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| FILTRE: Volatilité suffisante (ATR)                              |
//+------------------------------------------------------------------+
bool IsVolatilityOK()
{
   if(g_averageATR <= 0) return true;
   double ratio = g_currentATR / g_averageATR;
   if(ratio < ATR_Min_Multiplier)
   {
      Print("💤 Marché trop calme (ATR ", DoubleToString(ratio * 100, 0), "%)");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| FILTRE: Cooldown entre signaux                                   |
//+------------------------------------------------------------------+
bool IsCooldownRespected()
{
   if(g_lastSignalTime == 0) return true;
   int elapsedMinutes = (int)(TimeCurrent() - g_lastSignalTime) / 60;
   return (elapsedMinutes >= SignalCooldownMinutes);
}

//+------------------------------------------------------------------+
//| Vérification heures autorisées (Bénin GMT+1)                     |
//+------------------------------------------------------------------+
bool IsTimeAllowed()
{
   int brokerGMT = (BrokerGMTOffset != 0) ? BrokerGMTOffset : g_detectedBrokerGMT;
   int currentHour = Hour() - brokerGMT + 1;
   if(currentHour < 0) currentHour += 24;
   if(currentHour >= 24) currentHour -= 24;
   
   int dayOfWeek = DayOfWeek();
   
   if(dayOfWeek == 0 || dayOfWeek == 6) return false;
   if(FilterMonday && dayOfWeek == 1 && currentHour < 10) return false;
   if(FilterFriday && dayOfWeek == 5 && currentHour >= 18) return false;
   if(currentHour < StartHour || currentHour >= EndHour) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Vérification news (MT4 - Manuel)                                 |
//+------------------------------------------------------------------+
bool IsHighImpactNewsNear()
{
   if(!FilterHighImpactNews) return false;
   
   int currentTimeInt = Hour() * 100 + Minute();
   
   if(CheckNewsTime(NewsTime1, currentTimeInt)) return true;
   if(CheckNewsTime(NewsTime2, currentTimeInt)) return true;
   if(CheckNewsTime(NewsTime3, currentTimeInt)) return true;
   if(CheckNewsTime(NewsTime4, currentTimeInt)) return true;
   if(CheckNewsTime(NewsTime5, currentTimeInt)) return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Vérification proximité news                                      |
//+------------------------------------------------------------------+
bool CheckNewsTime(string newsTimeStr, int currentTimeInt)
{
   if(StringLen(newsTimeStr) != 4) return false;
   
   int newsTime = (int)StringToInteger(newsTimeStr);
   if(newsTime == 0) return false;
   
   int newsMinutes = (newsTime / 100) * 60 + (newsTime % 100);
   int currentMinutes = (currentTimeInt / 100) * 60 + (currentTimeInt % 100);
   int diff = MathAbs(currentMinutes - newsMinutes);
   
   return (diff <= NewsMinutesBefore || diff <= NewsMinutesAfter);
}

//+------------------------------------------------------------------+
//| Création panneau ENRICHI                                         |
//+------------------------------------------------------------------+
void CreatePanel()
{
   int x = 10;
   int y = 30;
   
   CreateLabel(g_panelName + "_title", "☠️ SWIFT REAPER PRO v3.2", x, y, PanelColor, 12);
   y += 22;
   CreateLabel(g_panelName + "_symbol", g_displayName, x, y, PanelColor, 14);
   y += 22;
   CreateLabel(g_panelName + "_sep1", "━━━━━━━━━━━━━━━━━━", x, y, PanelColor, 8);
   y += 16;
   CreateLabel(g_panelName + "_trend", "Tendance: ---", x, y, PanelColor, 10);
   y += 18;
   CreateLabel(g_panelName + "_adx", "ADX: --- | DI+: --- | DI-: ---", x, y, PanelColor, 9);
   y += 18;
   CreateLabel(g_panelName + "_atr", "Volatilité: ---", x, y, PanelColor, 9);
   y += 18;
   CreateLabel(g_panelName + "_rsi", "RSI M5: ---", x, y, PanelColor, 9);
   y += 18;
   CreateLabel(g_panelName + "_sep2", "━━━━━━━━━━━━━━━━━━", x, y, PanelColor, 8);
   y += 16;
   CreateLabel(g_panelName + "_state", "État: En attente", x, y, PanelColor, 10);
   y += 18;
   CreateLabel(g_panelName + "_spread", "Spread: --- pts", x, y, PanelColor, 9);
   y += 18;
   CreateLabel(g_panelName + "_mode", "Mode: ---", x, y, PanelColor, 9);
   y += 18;
   CreateLabel(g_panelName + "_time", "Heures: ---", x, y, PanelColor, 9);
   y += 18;
   CreateLabel(g_panelName + "_news", "News: ---", x, y, PanelColor, 9);
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
//| Mise à jour panneau ENRICHI                                      |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   // Tendance
   string trendText = "Tendance: ";
   color trendColor = PanelColor;
   switch(g_currentTrend)
   {
      case TREND_BULLISH: trendText += "HAUSSIÈRE ▲"; trendColor = clrGreen; break;
      case TREND_BEARISH: trendText += "BAISSIÈRE ▼"; trendColor = clrRed; break;
      case TREND_RANGE:   trendText += "RANGE ⏸️"; trendColor = clrDarkOrange; break;
      default:            trendText += "NEUTRE ●"; trendColor = clrGray; break;
   }
   ObjectSetString(0, g_panelName + "_trend", OBJPROP_TEXT, trendText);
   ObjectSetInteger(0, g_panelName + "_trend", OBJPROP_COLOR, trendColor);
   
   // ADX
   string adxText = "ADX: " + DoubleToString(g_currentADX, 1) +
                    " | DI+: " + DoubleToString(g_currentDIPlus, 1) +
                    " | DI-: " + DoubleToString(g_currentDIMinus, 1);
   color adxColor = (g_currentADX >= ADX_Strong) ? clrGreen : 
                    (g_currentADX >= ADX_Threshold) ? clrDarkOrange : clrRed;
   ObjectSetString(0, g_panelName + "_adx", OBJPROP_TEXT, adxText);
   ObjectSetInteger(0, g_panelName + "_adx", OBJPROP_COLOR, adxColor);
   
   // ATR
   string atrText = "Volatilité: ";
   color atrColor = PanelColor;
   if(g_averageATR > 0)
   {
      double ratio = g_currentATR / g_averageATR;
      if(ratio < ATR_Min_Multiplier) { atrText += "TROP CALME 💤"; atrColor = clrRed; }
      else if(ratio < 0.7) { atrText += "Faible (" + DoubleToString(ratio*100,0) + "%)"; atrColor = clrDarkOrange; }
      else { atrText += "OK (" + DoubleToString(ratio*100,0) + "%)"; atrColor = clrGreen; }
   }
   else atrText += "Calcul...";
   ObjectSetString(0, g_panelName + "_atr", OBJPROP_TEXT, atrText);
   ObjectSetInteger(0, g_panelName + "_atr", OBJPROP_COLOR, atrColor);
   
   // RSI
   string rsiText = "RSI M5: " + DoubleToString(g_currentRSI, 1);
   color rsiColor = PanelColor;
   if(g_currentRSI <= RSI_Oversold) { rsiText += " (SURVENTE 🔥)"; rsiColor = clrGreen; }
   else if(g_currentRSI >= RSI_Overbought) { rsiText += " (SURACHAT 🔥)"; rsiColor = clrRed; }
   else if(g_currentRSI < 40) { rsiText += " (zone basse)"; rsiColor = clrDarkOrange; }
   else if(g_currentRSI > 60) { rsiText += " (zone haute)"; rsiColor = clrDarkOrange; }
   else rsiText += " (neutre)";
   ObjectSetString(0, g_panelName + "_rsi", OBJPROP_TEXT, rsiText);
   ObjectSetInteger(0, g_panelName + "_rsi", OBJPROP_COLOR, rsiColor);
   
   // État
   string stateText = "État: ";
   color stateColor = PanelColor;
   if(g_inPosition)
   {
      string confText = (g_lastConfidence == CONFIDENCE_HIGH) ? " ⭐" : "";
      if(g_positionType == SIGNAL_BUY) { stateText += "EN POSITION BUY 🟢" + confText; stateColor = clrGreen; }
      else { stateText += "EN POSITION SELL 🔴" + confText; stateColor = clrRed; }
   }
   else { stateText += "En attente ⏳"; stateColor = clrDarkOrange; }
   ObjectSetString(0, g_panelName + "_state", OBJPROP_TEXT, stateText);
   ObjectSetInteger(0, g_panelName + "_state", OBJPROP_COLOR, stateColor);
   
   // Spread
   double spread = MarketInfo(g_symbol, MODE_SPREAD);
   string spreadText = "Spread: " + DoubleToString(spread, 0) + " pts";
   color spreadColor = PanelColor;
   if(spread > MaxSpreadPoints) { spreadText += " ⛔"; spreadColor = clrRed; }
   else if(spread > MaxSpreadPoints * 0.7) { spreadText += " ⚠️"; spreadColor = clrDarkOrange; }
   else { spreadText += " ✅"; spreadColor = clrGreen; }
   ObjectSetString(0, g_panelName + "_spread", OBJPROP_TEXT, spreadText);
   ObjectSetInteger(0, g_panelName + "_spread", OBJPROP_COLOR, spreadColor);
   
   // Mode
   string modeText = HighConfidenceOnly ? "Mode: HIGH ONLY ⭐" : "Mode: TOUS signaux";
   ObjectSetString(0, g_panelName + "_mode", OBJPROP_TEXT, modeText);
   ObjectSetInteger(0, g_panelName + "_mode", OBJPROP_COLOR, PanelColor);
   
   // Heures
   string timeText = IsTimeAllowed() ? "Heures: ACTIF ✅" : "Heures: INACTIF ❌";
   color timeColor = IsTimeAllowed() ? clrGreen : clrRed;
   ObjectSetString(0, g_panelName + "_time", OBJPROP_TEXT, timeText);
   ObjectSetInteger(0, g_panelName + "_time", OBJPROP_COLOR, timeColor);
   
   // News
   string newsText = "News: ";
   color newsColor = PanelColor;
   if(!FilterHighImpactNews) { newsText += "Filtre désactivé"; newsColor = clrGray; }
   else if(IsHighImpactNewsNear()) { newsText += "⚠️ NEWS PROCHE"; newsColor = clrRed; }
   else { newsText += "OK ✅"; newsColor = clrGreen; }
   ObjectSetString(0, g_panelName + "_news", OBJPROP_TEXT, newsText);
   ObjectSetInteger(0, g_panelName + "_news", OBJPROP_COLOR, newsColor);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Détection automatique GMT broker                                 |
//+------------------------------------------------------------------+
int DetectBrokerGMTOffset()
{
   if(BrokerGMTOffset != 0) return BrokerGMTOffset;
   datetime brokerTime = TimeCurrent();
   datetime gmtTime = TimeGMT();
   return (int)(brokerTime - gmtTime) / 3600;
}

//+------------------------------------------------------------------+
//| Sauvegarder état                                                 |
//+------------------------------------------------------------------+
void SaveState()
{
   int fileHandle = FileOpen(g_stateFileName, FILE_WRITE|FILE_TXT);
   if(fileHandle != INVALID_HANDLE)
   {
      string stateData = IntegerToString(g_inPosition ? 1 : 0) + "|" +
                         IntegerToString((int)g_positionType) + "|" +
                         IntegerToString((int)g_currentTrend) + "|" +
                         IntegerToString((int)g_lastConfidence) + "|" +
                         IntegerToString((long)g_lastSignalTime);
      FileWriteString(fileHandle, stateData);
      FileClose(fileHandle);
      Print("💾 État sauvegardé");
   }
}

//+------------------------------------------------------------------+
//| Charger état                                                     |
//+------------------------------------------------------------------+
void LoadState()
{
   if(!FileIsExist(g_stateFileName)) { Print("📄 Démarrage frais"); return; }
   
   int fileHandle = FileOpen(g_stateFileName, FILE_READ|FILE_TXT);
   if(fileHandle != INVALID_HANDLE)
   {
      string stateData = FileReadString(fileHandle);
      FileClose(fileHandle);
      
      string parts[];
      int count = StringSplit(stateData, '|', parts);
      
      if(count >= 3)
      {
         g_inPosition = (StrToInteger(parts[0]) == 1);
         g_positionType = (SIGNAL_TYPE)StrToInteger(parts[1]);
         g_currentTrend = (TREND_TYPE)StrToInteger(parts[2]);
         if(count >= 4) g_lastConfidence = (SIGNAL_CONFIDENCE)StrToInteger(parts[3]);
         if(count >= 5) g_lastSignalTime = (datetime)StrToInteger(parts[4]);
         
         Print("📂 État chargé: Position=", g_inPosition,
               ", Type=", EnumToString(g_positionType));
      }
   }
}

//+------------------------------------------------------------------+
//| Réinitialiser état                                               |
//+------------------------------------------------------------------+
void ResetState()
{
   g_inPosition = false;
   g_positionType = SIGNAL_NONE;
   g_lastSignal = SIGNAL_NONE;
   g_lastConfidence = CONFIDENCE_NONE;
   g_lastSignalTime = 0;
   if(FileIsExist(g_stateFileName)) FileDelete(g_stateFileName);
   Print("🔄 État réinitialisé");
}
//+------------------------------------------------------------------+
