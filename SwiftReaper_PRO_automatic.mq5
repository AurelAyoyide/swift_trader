//+------------------------------------------------------------------+
//|                                          SwiftReaper_PRO.mq5     |
//|                        Copyright 2026, SwiftReaper Development   |
//|                                    https://www.swiftreaper.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, SwiftReaper Development"
#property link      "https://www.swiftreaper.com"
#property version   "4.90"
#property description "SwiftReaper PRO v4.9 - Le Faucheur Ultime"
#property description "v4.9: Fermeture auto avant news + cooldown news réduit"
#property description "RSI 40/60 en tendance + filtre distance EMA + protection news"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum TREND_TYPE
{
   TREND_NONE,
   TREND_BULLISH,
   TREND_BEARISH,
   TREND_RANGE       // NOUVEAU: détection range via ADX (emprunté SwiftTrader)
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
   CONFIDENCE_MODERATE,  // Signal correct mais pas parfait
   CONFIDENCE_HIGH       // Toutes les étoiles sont alignées
};

//+------------------------------------------------------------------+
//| PARAMÈTRES D'ENTRÉE                                              |
//+------------------------------------------------------------------+
// Notifications
input group "=== NOTIFICATIONS ==="
input bool     EnableNotifications = true;       // Activer les notifications push
input bool     EnableAlerts = true;              // Activer les alertes sonores
input bool     HighConfidenceOnly = false;       // ONLY signaux HIGH (recommandé full margin)
input color    PanelColor = clrBlack;            // Couleur texte du panneau

// Timeframes
input group "=== TIMEFRAMES ==="
input ENUM_TIMEFRAMES TF_Trend = PERIOD_H1;      // Timeframe tendance (H1)
input ENUM_TIMEFRAMES TF_Entry = PERIOD_M5;      // Timeframe entrée (M5)

// Indicateurs Tendance (H1)
input group "=== TENDANCE H1 ==="
input int      EMA_Period = 50;                  // Période EMA (tendance H1)
input int      ADX_Period = 14;                  // Période ADX (force tendance)
input double   ADX_Threshold = 25.0;             // Seuil ADX minimum (< = RANGE, pas de trade)
input double   ADX_Strong = 30.0;                // ADX fort (signal confiance HIGH)

// Indicateurs Entrée (M5)
input group "=== ENTRÉE M5 ==="
input int      RSI_Period = 14;                  // Période RSI (entrée M5)
input int      RSI_Oversold = 40;                // RSI pullback BUY (40 = adapté tendance, Constance Brown)
input int      RSI_Overbought = 60;              // RSI pullback SELL (60 = adapté tendance, Constance Brown)
input int      RSI_Exit_TakeProfit = 80;         // RSI take profit (extrême - laisser courir en tendance)

// Filtres Avancés
input group "=== FILTRES AVANCÉS ==="
input int      ATR_Period = 14;                  // Période ATR (volatilité)
input double   ATR_Min_Multiplier = 0.3;         // ATR min vs moyenne (0.3 = 30%, marché mort)
input int      MaxSpreadPoints = 30;             // Spread max autorisé (en points)
input int      SignalCooldownMinutes = 30;        // Cooldown entre signaux (minutes)
input int      MinHoldMinutes = 30;              // Temps minimum en position (minutes, anti-scalping)
input double   MaxEMADistance_ATR = 2.5;         // Distance max prix-EMA50 en ATR (anti-chasing)

// Filtres horaires (Heure du Bénin GMT+1)
input group "=== FILTRES HORAIRES (Bénin GMT+1) ==="
input int      BrokerGMTOffset = 0;              // Décalage GMT broker (0=auto, 2=XM)
input int      StartHour = 8;                    // Heure début (08h00 Bénin)
input int      EndHour = 21;                     // Heure fin (21h00 Bénin)
input bool     FilterMonday = true;              // Éviter lundi avant 10h
input bool     FilterFriday = true;              // Éviter vendredi après 18h

// Filtre News
input group "=== FILTRE NEWS ==="
input bool     FilterHighImpactNews = true;      // Filtrer les news HIGH IMPACT
input int      NewsMinutesBefore = 30;           // Minutes avant news (pas de signal)
input int      NewsMinutesAfter = 30;            // Minutes après news (pas de signal)
input int      NewsCooldownMinutes = 5;          // Cooldown réduit après sortie news (5 min au lieu de 30)

// Identification
input group "=== IDENTIFICATION ==="
input string   PairName = "";                    // Nom personnalisé (vide = auto)

// Auto-Trading (optionnel)
input group "=== AUTO-TRADING (optionnel) ==="
input bool     EnableAutoTrading = false;        // Activer le trading automatique
input double   LotSize = 0.05;                   // Taille du lot
input bool     UseStopLoss = true;               // Utiliser un Stop Loss (basé ATR)
input double   StopLossATRMultiplier = 3.0;      // Stop Loss = X fois ATR H1 (filet de sécurité large)
input int      MagicNumber = 202602;             // Numéro magique (identifie nos ordres)
input int      MaxSlippage = 10;                 // Slippage max (points)

// Gestion du Trade (maximiser les gains)
input group "=== GESTION DU TRADE ==="
input bool     EnableTrailingStop = false;       // Trailing Stop (désactivé: les signaux gèrent les sorties)
input double   TrailingATRMultiplier = 2.0;      // Distance trailing = X fois ATR (si activé)
input bool     EnableAutoBreakeven = false;      // Breakeven auto (désactivé: pas de BE prématuré)
input double   BreakevenATRMultiplier = 1.5;     // Breakeven quand profit = X fois ATR (1.5 = laisse respirer)

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                               |
//+------------------------------------------------------------------+
// État du système
TREND_TYPE g_currentTrend = TREND_NONE;
SIGNAL_TYPE g_lastSignal = SIGNAL_NONE;
SIGNAL_CONFIDENCE g_lastConfidence = CONFIDENCE_NONE;
bool g_inPosition = false;
SIGNAL_TYPE g_positionType = SIGNAL_NONE;

// Données tendance (pour panneau et décisions)
double g_currentADX = 0;
double g_currentDIPlus = 0;
double g_currentDIMinus = 0;
double g_currentATR = 0;
double g_averageATR = 0;
double g_currentRSI = 0;
double g_currentSpread = 0;

// Symbole
string g_symbol;
string g_displayName;

// Handles indicateurs
int g_emaH1Handle;        // EMA 50 H1 (tendance)
int g_adxH1Handle;        // ADX H1 (force tendance + DI)
int g_atrH1Handle;        // ATR H1 (volatilité)
int g_rsiM5Handle;        // RSI 14 M5 (entrée)

// Tracking bougies
datetime g_lastH1Candle = 0;
datetime g_lastM5Candle = 0;

// Cooldown
datetime g_lastSignalTime = 0;

// EMA50 H1 (pour filtre distance dans entrée)
double g_currentEMA50 = 0;

// Protection breakeven
bool g_breakevenNotified = false;

// Trailing stop & breakeven
double g_entryPrice = 0;
datetime g_entryTime = 0;
bool g_breakevenApplied = false;

// DI à l'entrée (pour détecter un VRAI croisement, pas un état existant)
double g_entryDIPlus = 0;
double g_entryDIMinus = 0;

// v4.9: Sortie news = cooldown réduit
bool g_lastExitWasNews = false;

// Nom objets graphiques
string g_panelName = "SwiftReaperPRO";

// Fichier sauvegarde
string g_stateFileName;

// GMT
int g_detectedBrokerGMT = 0;

// Objet Trade (auto-trading)
CTrade g_trade;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialisation symbole
   g_symbol = Symbol();
   g_displayName = (PairName != "") ? PairName : g_symbol;
   
   // Fichier de sauvegarde unique par paire
   g_stateFileName = "SwiftReaperPRO_" + g_symbol + "_state.txt";
   
   // Détection automatique GMT broker
   g_detectedBrokerGMT = DetectBrokerGMTOffset();
   Print("🌍 GMT Broker détecté: GMT+", g_detectedBrokerGMT);
   
   // === CRÉATION HANDLES INDICATEURS ===
   
   // H1 - Tendance
   g_emaH1Handle = iMA(g_symbol, TF_Trend, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   g_adxH1Handle = iADX(g_symbol, TF_Trend, ADX_Period);
   g_atrH1Handle = iATR(g_symbol, TF_Trend, ATR_Period);
   
   // M5 - Entrée
   g_rsiM5Handle = iRSI(g_symbol, TF_Entry, RSI_Period, PRICE_CLOSE);
   
   // Vérification handles
   if(g_emaH1Handle == INVALID_HANDLE || g_adxH1Handle == INVALID_HANDLE || 
      g_atrH1Handle == INVALID_HANDLE || g_rsiM5Handle == INVALID_HANDLE)
   {
      Print("❌ Erreur création indicateurs");
      return INIT_FAILED;
   }
   
   // Charger état sauvegardé
   LoadState();
   
   // Panneau
   CreatePanel();
   
   // Timer
   EventSetTimer(1);
   
   // Détection tendance initiale
   DetectTrend();
   
   // Configuration auto-trading
   if(EnableAutoTrading)
   {
      g_trade.SetExpertMagicNumber(MagicNumber);
      g_trade.SetDeviationInPoints(MaxSlippage);
      // Auto-détection du mode de remplissage (compatibilité broker)
      long fillMode = SymbolInfoInteger(g_symbol, SYMBOL_FILLING_MODE);
      if((fillMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
         g_trade.SetTypeFilling(ORDER_FILLING_FOK);
      else if((fillMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
         g_trade.SetTypeFilling(ORDER_FILLING_IOC);
      else
         g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
      Print("🤖 AUTO-TRADING ACTIVÉ | Lot: ", DoubleToString(LotSize, 2),
            " | SL: ", (UseStopLoss ? DoubleToString(StopLossATRMultiplier, 1) + "x ATR" : "Désactivé"));
   }
   
   Print("✅ SwiftReaper PRO v4.8 initialisé sur ", g_displayName);
   if(HighConfidenceOnly)
      Print("⭐ MODE: HIGH CONFIDENCE ONLY (full margin)");
   Print("📍 Mode: ", EnableAutoTrading ? "AUTO-TRADING" : "Notifications uniquement");
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
   // Sauvegarder état
   SaveState();
   
   // Libération handles
   if(g_emaH1Handle != INVALID_HANDLE) IndicatorRelease(g_emaH1Handle);
   if(g_adxH1Handle != INVALID_HANDLE) IndicatorRelease(g_adxH1Handle);
   if(g_atrH1Handle != INVALID_HANDLE) IndicatorRelease(g_atrH1Handle);
   if(g_rsiM5Handle != INVALID_HANDLE) IndicatorRelease(g_rsiM5Handle);
   
   // Suppression objets graphiques
   ObjectsDeleteAll(0, g_panelName);
   
   EventKillTimer();
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Mise à jour spread en temps réel
   g_currentSpread = (double)SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);
   
   // FIX v4.6: Si tendance encore inconnue (données pas chargées au démarrage), réessayer
   // Sans ça, le panneau reste "NEUTRE" jusqu'à 59 min et aucun signal ne peut partir
   if(g_currentTrend == TREND_NONE)
      DetectTrend();
   
   // Vérification nouvelles bougies fermées
   CheckNewCandles();
   
   // SYNC: Détecter si la position a été fermée manuellement
   if(EnableAutoTrading && g_inPosition && !HasOpenPosition())
   {
      Print("⚠️ Position fermée manuellement - Reset état");
      g_inPosition = false;
      g_positionType = SIGNAL_NONE;
      g_lastSignal = SIGNAL_NONE;
      g_lastConfidence = CONFIDENCE_NONE;
      g_breakevenNotified = false;
      g_breakevenApplied = false;
      g_entryPrice = 0;
      g_entryTime = 0;
      g_entryDIPlus = 0;
      g_entryDIMinus = 0;
      SaveState();
   }
   
   // v4.9: PROTECTION NEWS - Fermer position si news HIGH IMPACT dans < 30 min
   if(g_inPosition && FilterHighImpactNews && IsHighImpactNewsNear())
   {
      SendExitSignal("📰 NEWS HIGH IMPACT imminente - Protection capital!");
      g_lastExitWasNews = true;  // Cooldown réduit après sortie news
   }
   
   // TRAILING STOP + BREAKEVEN (chaque tick, pas chaque bougie)
   if(EnableAutoTrading && g_inPosition && HasOpenPosition())
   {
      ManageTrailingStop();
   }
   
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
   
   if(CopyTime(g_symbol, TF_Trend, 0, 2, h1Time) < 2) return;
   if(CopyTime(g_symbol, TF_Entry, 0, 2, m5Time) < 2) return;
   
   // === Nouvelle bougie H1 FERMÉE ===
   if(h1Time[1] > g_lastH1Candle && g_lastH1Candle != 0)
   {
      TREND_TYPE previousTrend = g_currentTrend;
      DetectTrend();
      
      // Si tendance H1 se RETOURNE ou MEURT → SORTIE
      if(g_inPosition)
      {
         // 1. Retournement complet (prix passe de l'autre côté de EMA50) → sortie immédiate
         if(g_positionType == SIGNAL_BUY && g_currentTrend == TREND_BEARISH)
         {
            SendExitSignal("⚠️ TENDANCE H1 RETOURNÉE BAISSIÈRE - SORS!");
         }
         else if(g_positionType == SIGNAL_SELL && g_currentTrend == TREND_BULLISH)
         {
            SendExitSignal("⚠️ TENDANCE H1 RETOURNÉE HAUSSIÈRE - SORS!");
         }
         // 2. v4.7: Tendance morte (ADX < seuil = RANGE) → sortie après minHold
         //    La prémisse du trade (tendance forte) n'existe plus
         else if(g_currentTrend == TREND_RANGE)
         {
            int holdMin = (g_entryTime > 0) ? (int)(TimeCurrent() - g_entryTime) / 60 : 999;
            if(holdMin >= MinHoldMinutes)
            {
               SendExitSignal("📉 H1 passée en RANGE (ADX < " + DoubleToString(ADX_Threshold, 0) + ") - Tendance morte");
            }
         }
      }
   }
   g_lastH1Candle = h1Time[1];
   
   // === Nouvelle bougie M5 FERMÉE ===
   if(m5Time[1] > g_lastM5Candle && g_lastM5Candle != 0)
   {
      // Toujours mettre à jour le RSI pour le panneau
      UpdateRSI();
      
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
   g_lastM5Candle = m5Time[1];
}

//+------------------------------------------------------------------+
//| Détection tendance H1 (EMA50 + ADX + DI+/DI-)                   |
//| Fusion: SwiftReaper EMA + SwiftTrader ADX/DI                     |
//+------------------------------------------------------------------+
void DetectTrend()
{
   double emaValues[];
   double closePrice[];
   double adxValues[];
   double diPlusValues[];
   double diMinusValues[];
   double atrValues[];
   
   ArraySetAsSeries(emaValues, true);
   ArraySetAsSeries(closePrice, true);
   ArraySetAsSeries(adxValues, true);
   ArraySetAsSeries(diPlusValues, true);
   ArraySetAsSeries(diMinusValues, true);
   ArraySetAsSeries(atrValues, true);
   
   // Copie indicateurs H1 (bougie fermée = index 1)
   if(CopyBuffer(g_emaH1Handle, 0, 0, 3, emaValues) < 3) return;
   if(CopyClose(g_symbol, TF_Trend, 0, 3, closePrice) < 3) return;
   if(CopyBuffer(g_adxH1Handle, 0, 0, 3, adxValues) < 3) return;      // ADX main
   if(CopyBuffer(g_adxH1Handle, 1, 0, 3, diPlusValues) < 3) return;   // +DI
   if(CopyBuffer(g_adxH1Handle, 2, 0, 3, diMinusValues) < 3) return;  // -DI
   
   // ATR (récupérer plus pour calculer la moyenne)
   double atrLong[];
   ArraySetAsSeries(atrLong, true);
   if(CopyBuffer(g_atrH1Handle, 0, 0, 51, atrLong) < 51) return;
   
   // Stocker valeurs actuelles pour panneau et filtres
   g_currentADX = adxValues[1];
   g_currentDIPlus = diPlusValues[1];
   g_currentDIMinus = diMinusValues[1];
   g_currentATR = atrLong[1];
   g_currentEMA50 = emaValues[1];  // v4.8: stocké pour filtre distance dans CheckEntrySignal
   
   // Calcul ATR moyen (50 dernières bougies fermées)
   double atrSum = 0;
   for(int i = 1; i <= 50; i++)
      atrSum += atrLong[i];
   g_averageATR = atrSum / 50.0;
   
   // === LOGIQUE DE TENDANCE (3 couches) ===
   TREND_TYPE previousTrend = g_currentTrend;
   
   // Couche 1: Prix vs EMA 50 (direction de base - SwiftReaper)
   bool priceAboveEMA = closePrice[1] > emaValues[1];
   bool priceBelowEMA = closePrice[1] < emaValues[1];
   
   // Couche 2: ADX (force de tendance - SwiftTrader)
   bool trendExists = g_currentADX >= ADX_Threshold;
   
   // Couche 3: DI+/DI- (confirmation directionnelle - SwiftTrader)
   bool diConfirmsBull = g_currentDIPlus > g_currentDIMinus;
   bool diConfirmsBear = g_currentDIMinus > g_currentDIPlus;
   
   // === DÉCISION FINALE ===
   if(!trendExists)
   {
      // ADX trop faible = RANGE = PAS DE TRADE
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
      // Prix en-dessous EMA50 = BAISSIÈRE
      g_currentTrend = TREND_BEARISH;
   }
   else
   {
      g_currentTrend = TREND_RANGE;
   }
   
   // Log si changement
   if(previousTrend != g_currentTrend)
   {
      string trendNames[] = {"NEUTRE", "HAUSSIÈRE 📈", "BAISSIÈRE 📉", "RANGE ⏸️"};
      string msg = "🔄 SWIFT REAPER PRO - " + g_displayName + "\n" +
                   "Tendance: " + trendNames[g_currentTrend] + "\n" +
                   "ADX: " + DoubleToString(g_currentADX, 1) + 
                   " | DI+: " + DoubleToString(g_currentDIPlus, 1) +
                   " | DI-: " + DoubleToString(g_currentDIMinus, 1);
      Print(msg);
      
      // NOUVEAU: Notification quand on SORT du range (nouvelle tendance commence)
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
//| v4.8: RSI ajusté pour tendance (Constance Brown / Fidelity)      |
//| En uptrend: RSI range 40-90, support à 40-50 (pas 30!)           |
//| En downtrend: RSI range 10-60, résistance à 50-60 (pas 70!)     |
//| + Filtre distance EMA50 (anti-chasing)                           |
//+------------------------------------------------------------------+
void CheckEntrySignal()
{
   // === FILTRE 1: Tendance claire (pas de range, pas neutre) ===
   if(g_currentTrend == TREND_NONE || g_currentTrend == TREND_RANGE) return;
   
   // === FILTRE 2: Volatilité suffisante (ATR) ===
   if(!IsVolatilityOK())
   {
      return;
   }
   
   // === FILTRE 3: Spread acceptable ===
   if(!IsSpreadAcceptable())
   {
      return;
   }
   
   // === FILTRE 4: Cooldown entre signaux ===
   if(!IsCooldownRespected())
   {
      return;
   }
   
   // === DONNÉES M5 ===
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
   
   if(CopyBuffer(g_rsiM5Handle, 0, 0, 3, rsiValues) < 3) return;
   if(CopyClose(g_symbol, TF_Entry, 0, 3, closePrice) < 3) return;
   if(CopyOpen(g_symbol, TF_Entry, 0, 3, openPrice) < 3) return;
   if(CopyHigh(g_symbol, TF_Entry, 0, 3, highPrice) < 3) return;
   if(CopyLow(g_symbol, TF_Entry, 0, 3, lowPrice) < 3) return;
   
   // RSI sur bougie fermée
   double rsi = rsiValues[1];
   double rsiPrev = rsiValues[2];
   g_currentRSI = rsi;
   
   // === FILTRE 5 (v4.8): Distance EMA50 - anti-chasing ===
   // Si prix trop loin de EMA50, on chasse un mouvement étendu = risqué
   if(g_currentEMA50 > 0 && g_currentATR > 0)
   {
      double emaDistance = MathAbs(closePrice[1] - g_currentEMA50);
      if(emaDistance > g_currentATR * MaxEMADistance_ATR)
      {
         Print("⏭️ Prix trop loin de EMA50 (", DoubleToString(emaDistance / g_currentATR, 1), 
               "x ATR > ", DoubleToString(MaxEMADistance_ATR, 1), "x) - anti-chasing");
         return;
      }
   }
   
   // Bougie de confirmation
   bool bullishCandle = closePrice[1] > openPrice[1];
   bool bearishCandle = closePrice[1] < openPrice[1];
   
   // Pin bar / bougie de rejet
   double bodySize = MathAbs(closePrice[1] - openPrice[1]);
   double upperWick = highPrice[1] - MathMax(closePrice[1], openPrice[1]);
   double lowerWick = MathMin(closePrice[1], openPrice[1]) - lowPrice[1];
   
   bool bullishRejection = (lowerWick > bodySize * 1.5) && bullishCandle;
   bool bearishRejection = (upperWick > bodySize * 1.5) && bearishCandle;
   
   // === SIGNAL BUY ===
   if(g_currentTrend == TREND_BULLISH)
   {
      // v4.8: RSI sort de zone pullback (40 par défaut, pas 30)
      // En uptrend, le RSI reste dans 40-90 (Constance Brown / Fidelity)
      // RSI < 40 = pullback → RSI repasse au-dessus = momentum reprend
      // OU RSI bas avec mèche forte de rejet (pin bar)
      bool rsiExitOversold = (rsiPrev <= RSI_Oversold && rsi > RSI_Oversold);
      bool rsiWithStrongRejection = (rsi < (RSI_Oversold + 5) && bullishRejection && lowerWick > bodySize * 2.0);
      
      bool rsiCondition = rsiExitOversold || rsiWithStrongRejection;
      
      if(rsiCondition && bullishCandle)
      {
         // Filtre corps minimum: pas de doji (sauf pin bar qui a un petit corps par nature)
         if(!rsiWithStrongRejection && bodySize < g_currentATR * 0.1)
         {
            Print("⏭️ Bougie trop petite (doji) - signal BUY ignoré");
            return;
         }
         SIGNAL_CONFIDENCE confidence = CalculateConfidence(SIGNAL_BUY, rsi, rsiPrev, bodySize, lowerWick);
         if(HighConfidenceOnly && confidence != CONFIDENCE_HIGH)
         {
            Print("⏭️ Signal BUY MODERATE ignoré (mode HIGH only)");
            return;
         }
         SendEntrySignal(SIGNAL_BUY, confidence);
         g_breakevenNotified = false;
         return;
      }
   }
   
   // === SIGNAL SELL ===
   if(g_currentTrend == TREND_BEARISH)
   {
      // v4.8: RSI sort de zone pullback (60 par défaut, pas 70)
      // En downtrend, le RSI reste dans 10-60 (Constance Brown / Fidelity)
      // RSI > 60 = pullback → RSI repasse en-dessous = momentum reprend
      bool rsiExitOverbought = (rsiPrev >= RSI_Overbought && rsi < RSI_Overbought);
      bool rsiWithStrongRejection = (rsi > (RSI_Overbought - 5) && bearishRejection && upperWick > bodySize * 2.0);
      
      bool rsiCondition = rsiExitOverbought || rsiWithStrongRejection;
      
      if(rsiCondition && bearishCandle)
      {
         // Filtre corps minimum: pas de doji (sauf pin bar de rejet)
         if(!rsiWithStrongRejection && bodySize < g_currentATR * 0.1)
         {
            Print("⏭️ Bougie trop petite (doji) - signal SELL ignoré");
            return;
         }
         SIGNAL_CONFIDENCE confidence = CalculateConfidence(SIGNAL_SELL, rsi, rsiPrev, bodySize, upperWick);
         if(HighConfidenceOnly && confidence != CONFIDENCE_HIGH)
         {
            Print("⏭️ Signal SELL MODERATE ignoré (mode HIGH only)");
            return;
         }
         SendEntrySignal(SIGNAL_SELL, confidence);
         g_breakevenNotified = false;
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Vérification signal de SORTIE (M5 bougie FERMÉE)                 |
//| v4.7: Sorties basées sur H1, plus de bruit M5                   |
//| Philosophie: on entre sur H1+M5, on sort sur H1+extrêmes M5     |
//| SUPPRIMÉ: EMA21 M5, engulfing normal M5, RSI Secure M5          |
//| GARDÉ: RSI extrême M5, Engulfing MASSIF M5 (>50% ATR)           |
//| AJOUTÉ: DI Cross H1 (vendeurs/acheteurs prennent le contrôle)   |
//+------------------------------------------------------------------+
void CheckExitSignal()
{
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
   
   if(CopyBuffer(g_rsiM5Handle, 0, 0, 3, rsiValues) < 3) return;
   if(CopyClose(g_symbol, TF_Entry, 0, 3, closePrice) < 3) return;
   if(CopyOpen(g_symbol, TF_Entry, 0, 3, openPrice) < 3) return;
   if(CopyHigh(g_symbol, TF_Entry, 0, 3, highPrice) < 3) return;
   if(CopyLow(g_symbol, TF_Entry, 0, 3, lowPrice) < 3) return;
   
   double rsi = rsiValues[1];
   g_currentRSI = rsi;
   bool shouldExit = false;
   string exitReason = "";
   
   double bodySize1 = MathAbs(closePrice[1] - openPrice[1]);
   double bodySize2 = MathAbs(closePrice[2] - openPrice[2]);
   double pointSize = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   
   // === TEMPS MINIMUM EN POSITION ===
   int holdMinutes = (g_entryTime > 0) ? (int)(TimeCurrent() - g_entryTime) / 60 : 999;
   bool minHoldReached = (holdMinutes >= MinHoldMinutes);
   
   // === NOTIFICATION BREAKEVEN (mode manuel uniquement) ===
   if(!EnableAutoTrading && !g_breakevenNotified && !g_breakevenApplied)
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
      // 1. ENGULFING MASSIF M5 (corps > 50% ATR H1)
      //    Un engulfing normal M5 = bruit de pullback en tendance H1, on l'IGNORE
      //    Seul un engulfing MASSIF (crash violent) justifie une sortie depuis M5
      bool bearishEngulfing = (closePrice[1] < openPrice[1]) &&
                               (openPrice[1] >= closePrice[2]) &&
                               (closePrice[1] <= openPrice[2]) &&
                               (bodySize1 > bodySize2 * 1.2) &&
                               (bodySize2 > pointSize * 5) &&
                               (bodySize1 > g_currentATR * 0.5);  // >50% ATR = MASSIF uniquement
      if(bearishEngulfing && minHoldReached)
      {
         shouldExit = true;
         exitReason = "⚠️ ENGULFING MASSIF baissier (>50% ATR) - Retournement violent!";
      }
      
      // 2. RSI EXTRÊME - take profit (le marché a donné tout ce qu'il avait)
      if(rsi >= RSI_Exit_TakeProfit && !shouldExit && minHoldReached)
      {
         shouldExit = true;
         exitReason = "🎯 RSI " + IntegerToString(RSI_Exit_TakeProfit) + "+ Take profit!";
      }
      
      // 3. DI CROSS H1 - les vendeurs prennent le contrôle de la tendance
      //    Condition: DI était en notre faveur à l'entrée ET s'est retourné
      //    Seulement si ADX < 30 (en tendance super forte, le DI cross est temporaire)
      //    Écart minimum de 5 points pour filtrer les croisements rasants
      if(!shouldExit && minHoldReached && g_currentADX < ADX_Strong)
      {
         bool diWasInFavor = (g_entryDIPlus > g_entryDIMinus);
         bool diNowAgainst = (g_currentDIMinus > g_currentDIPlus);
         double diGap = g_currentDIMinus - g_currentDIPlus;
         
         if(diWasInFavor && diNowAgainst && diGap >= 5.0)
         {
            shouldExit = true;
            exitReason = "📊 DI- > DI+ de " + DoubleToString(diGap, 1) + " (H1) - Vendeurs prennent le contrôle";
         }
      }
   }
   
   // === SORTIE POSITION SELL ===
   if(g_positionType == SIGNAL_SELL)
   {
      // 1. ENGULFING MASSIF M5 (corps > 50% ATR H1)
      bool bullishEngulfing = (closePrice[1] > openPrice[1]) &&
                               (openPrice[1] <= closePrice[2]) &&
                               (closePrice[1] >= openPrice[2]) &&
                               (bodySize1 > bodySize2 * 1.2) &&
                               (bodySize2 > pointSize * 5) &&
                               (bodySize1 > g_currentATR * 0.5);
      if(bullishEngulfing && minHoldReached)
      {
         shouldExit = true;
         exitReason = "⚠️ ENGULFING MASSIF haussier (>50% ATR) - Retournement violent!";
      }
      
      // 2. RSI EXTRÊME - take profit
      if(rsi <= (100 - RSI_Exit_TakeProfit) && !shouldExit && minHoldReached)
      {
         shouldExit = true;
         exitReason = "🎯 RSI " + IntegerToString(100 - RSI_Exit_TakeProfit) + "- Take profit!";
      }
      
      // 3. DI CROSS H1 - les acheteurs prennent le contrôle
      if(!shouldExit && minHoldReached && g_currentADX < ADX_Strong)
      {
         bool diWasInFavor = (g_entryDIMinus > g_entryDIPlus);
         bool diNowAgainst = (g_currentDIPlus > g_currentDIMinus);
         double diGap = g_currentDIPlus - g_currentDIMinus;
         
         if(diWasInFavor && diNowAgainst && diGap >= 5.0)
         {
            shouldExit = true;
            exitReason = "📊 DI+ > DI- de " + DoubleToString(diGap, 1) + " (H1) - Acheteurs prennent le contrôle";
         }
      }
   }
   
   if(shouldExit)
   {
      g_breakevenNotified = false;
      SendExitSignal(exitReason);
   }
}

//+------------------------------------------------------------------+
//| Calcul niveau de confiance du signal                             |
//+------------------------------------------------------------------+
SIGNAL_CONFIDENCE CalculateConfidence(SIGNAL_TYPE signal, double rsi, double rsiPrev, double bodySize, double wickSize)
{
   int score = 0;
   
   // 1. ADX fort (tendance très forte) = +2
   if(g_currentADX >= ADX_Strong)
      score += 2;
   else
      score += 1;
   
   // 2. v4.8: Profondeur du pullback RSI (ajusté pour tendance)
   //    Pullback profond (RSI < 30 BUY ou > 70 SELL) = très rare en tendance = signal fort
   //    Pullback standard (RSI dans la zone d'entrée) = signal normal
   if(signal == SIGNAL_BUY && rsiPrev < 30)
      score += 2;  // Pullback profond rare en uptrend = conviction forte
   else if(signal == SIGNAL_SELL && rsiPrev > 70)
      score += 2;  // Pullback profond rare en downtrend = conviction forte
   else if(signal == SIGNAL_BUY && rsiPrev <= RSI_Oversold)
      score += 1;  // Pullback standard (zone d'entrée)
   else if(signal == SIGNAL_SELL && rsiPrev >= RSI_Overbought)
      score += 1;  // Pullback standard (zone d'entrée)
   
   // 3. Mèche de rejet forte (pin bar) = +2
   if(wickSize > bodySize * 2.5)
      score += 2;
   else if(wickSize > bodySize * 1.5)
      score += 1;
   
   // 4. DI confirme la direction = +2, DI séparé = +1 bonus
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
         score += 1; // Bonus: DI très séparé
   }
   // Si DI ne confirme pas = 0 points (pullback en cours, pas pénalisé mais pas bonus)
   
   // 5. Bonne volatilité (ATR pas trop faible) = +1
   if(g_averageATR > 0 && g_currentATR > g_averageATR * 0.6)
      score += 1;
   
   // Score: 0-4 = MODERATE, 5+ = HIGH
   if(score >= 5)
      return CONFIDENCE_HIGH;
   else
      return CONFIDENCE_MODERATE;
}

//+------------------------------------------------------------------+
//| Envoi signal d'ENTRÉE (avec niveau de confiance)                 |
//+------------------------------------------------------------------+
void SendEntrySignal(SIGNAL_TYPE signal, SIGNAL_CONFIDENCE confidence)
{
   g_lastSignal = signal;
   g_lastConfidence = confidence;
   g_inPosition = true;
   g_positionType = signal;
   g_lastSignalTime = TimeCurrent();
   g_entryTime = TimeCurrent();
   g_breakevenApplied = false;
   
   // Stocker DI à l'entrée (pour détecter un VRAI croisement plus tard)
   g_entryDIPlus = g_currentDIPlus;
   g_entryDIMinus = g_currentDIMinus;
   
   // Stocker prix d'entrée
   if(signal == SIGNAL_BUY)
      g_entryPrice = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   else
      g_entryPrice = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   
   // Sauvegarder immédiatement
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
   
   if(EnableAlerts)
      Alert(msg);
   
   if(EnableNotifications)
      SendNotification(msg);
   
   // === AUTO-TRADING: Ouvrir position ===
   if(EnableAutoTrading)
   {
      if(!OpenPosition(signal))
      {
         Print("⚠️ Échec ouverture position - état réinitialisé");
         g_inPosition = false;
         g_positionType = SIGNAL_NONE;
         g_breakevenApplied = false;
         g_entryPrice = 0;
         g_entryTime = 0;
         SaveState();
      }
   }
}
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
   
   if(EnableAlerts)
      Alert(msg);
   
   if(EnableNotifications)
      SendNotification(msg);
   
   // === AUTO-TRADING: Fermer position ===
   ClosePosition();
   
   // Reset état
   g_inPosition = false;
   g_positionType = SIGNAL_NONE;
   g_lastSignal = SIGNAL_NONE;
   g_lastConfidence = CONFIDENCE_NONE;
   g_breakevenApplied = false;
   g_entryPrice = 0;
   g_entryTime = 0;
   
   g_breakevenNotified = false;
   g_entryDIPlus = 0;
   g_entryDIMinus = 0;
   
   // Cooldown après EXIT aussi (anti-cycling)
   g_lastSignalTime = TimeCurrent();
   
   // Sauvegarder immédiatement
   SaveState();
}

//+------------------------------------------------------------------+
//| FILTRE: Spread acceptable                                        |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
   long spread = SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);
   
   if(spread > MaxSpreadPoints)
   {
      Print("⛔ Spread trop élevé: ", spread, " pts (max: ", MaxSpreadPoints, ")");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| FILTRE: Volatilité suffisante (ATR)                              |
//+------------------------------------------------------------------+
bool IsVolatilityOK()
{
   if(g_averageATR <= 0) return true; // Pas encore de données
   
   double ratio = g_currentATR / g_averageATR;
   
   if(ratio < ATR_Min_Multiplier)
   {
      Print("💤 Marché trop calme - ATR: ", DoubleToString(g_currentATR, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)),
            " vs Moyenne: ", DoubleToString(g_averageATR, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)),
            " (Ratio: ", DoubleToString(ratio * 100, 0), "%)");
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
   
   datetime currentTime = TimeCurrent();
   int elapsedMinutes = (int)(currentTime - g_lastSignalTime) / 60;
   
   // v4.9: Cooldown réduit après sortie news (5 min au lieu de 30)
   int cooldownToUse = g_lastExitWasNews ? NewsCooldownMinutes : SignalCooldownMinutes;
   
   if(elapsedMinutes < cooldownToUse)
   {
      return false;
   }
   
   // Reset flag news une fois cooldown passé
   if(g_lastExitWasNews)
      g_lastExitWasNews = false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Vérification heures autorisées (Bénin GMT+1)                     |
//+------------------------------------------------------------------+
bool IsTimeAllowed()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   int brokerGMT = (BrokerGMTOffset != 0) ? BrokerGMTOffset : g_detectedBrokerGMT;
   
   int currentHour = dt.hour - brokerGMT + 1;
   if(currentHour < 0) currentHour += 24;
   if(currentHour >= 24) currentHour -= 24;
   
   int dayOfWeek = dt.day_of_week;
   
   // Weekend
   if(dayOfWeek == 0 || dayOfWeek == 6)
      return false;
   
   // Lundi avant 10h
   if(FilterMonday && dayOfWeek == 1 && currentHour < 10)
      return false;
   
   // Vendredi après 18h
   if(FilterFriday && dayOfWeek == 5 && currentHour >= 18)
      return false;
   
   // Heures normales
   if(currentHour < StartHour || currentHour >= EndHour)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Vérification news HIGH IMPACT (MT5 natif)                        |
//+------------------------------------------------------------------+
bool IsHighImpactNewsNear()
{
   if(!FilterHighImpactNews)
      return false;
   
   datetime currentTime = TimeCurrent();
   datetime startTime = currentTime - NewsMinutesAfter * 60;
   datetime endTime = currentTime + NewsMinutesBefore * 60;
   
   MqlCalendarValue values[];
   int count = CalendarValueHistory(values, startTime, endTime);
   
   if(count <= 0)
      return false;
   
   for(int i = 0; i < count; i++)
   {
      MqlCalendarEvent event;
      if(CalendarEventById(values[i].event_id, event))
      {
         if(event.importance == CALENDAR_IMPORTANCE_HIGH)
         {
            MqlCalendarCountry country;
            if(CalendarCountryById(event.country_id, country))
            {
               string currency = country.currency;
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
//| Création panneau d'affichage ENRICHI                             |
//+------------------------------------------------------------------+
void CreatePanel()
{
   int x = 10;
   int y = 30;
   
   // Titre
   CreateLabel(g_panelName + "_title", "☠️ SWIFT REAPER PRO v4.9", x, y, PanelColor, 12);
   y += 22;
   
   // Symbole
   CreateLabel(g_panelName + "_symbol", g_displayName, x, y, PanelColor, 14);
   y += 22;
   
   // Séparateur
   CreateLabel(g_panelName + "_sep1", "━━━━━━━━━━━━━━━━━━", x, y, PanelColor, 8);
   y += 16;
   
   // Tendance
   CreateLabel(g_panelName + "_trend", "Tendance: ---", x, y, PanelColor, 10);
   y += 18;
   
   // ADX
   CreateLabel(g_panelName + "_adx", "ADX: --- | DI+: --- | DI-: ---", x, y, PanelColor, 9);
   y += 18;
   
   // ATR / Volatilité
   CreateLabel(g_panelName + "_atr", "Volatilité: ---", x, y, PanelColor, 9);
   y += 18;
   
   // RSI
   CreateLabel(g_panelName + "_rsi", "RSI M5: ---", x, y, PanelColor, 9);
   y += 18;
   
   // Séparateur
   CreateLabel(g_panelName + "_sep2", "━━━━━━━━━━━━━━━━━━", x, y, PanelColor, 8);
   y += 16;
   
   // État
   CreateLabel(g_panelName + "_state", "État: En attente", x, y, PanelColor, 10);
   y += 18;
   
   // Spread
   CreateLabel(g_panelName + "_spread", "Spread: --- pts", x, y, PanelColor, 9);
   y += 18;
   
   // Mode
   CreateLabel(g_panelName + "_mode", "Mode: ---", x, y, PanelColor, 9);
   y += 18;
   
   // Auto-trade
   CreateLabel(g_panelName + "_autotrade", "Auto: ---", x, y, PanelColor, 9);
   y += 18;
   
   // Filtre horaire
   CreateLabel(g_panelName + "_time", "Heures: ---", x, y, PanelColor, 9);
   y += 18;
   
   // Filtre news
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
   // === TENDANCE ===
   string trendText = "Tendance: ";
   color trendColor = PanelColor;
   
   switch(g_currentTrend)
   {
      case TREND_BULLISH:
         trendText += "HAUSSIÈRE ▲";
         trendColor = clrGreen;
         break;
      case TREND_BEARISH:
         trendText += "BAISSIÈRE ▼";
         trendColor = clrRed;
         break;
      case TREND_RANGE:
         trendText += "RANGE ⏸️ (pas de trade)";
         trendColor = clrDarkOrange;
         break;
      default:
         trendText += "NEUTRE ●";
         trendColor = clrGray;
   }
   ObjectSetString(0, g_panelName + "_trend", OBJPROP_TEXT, trendText);
   ObjectSetInteger(0, g_panelName + "_trend", OBJPROP_COLOR, trendColor);
   
   // === ADX + DI ===
   string adxText = "ADX: " + DoubleToString(g_currentADX, 1) + 
                    " | DI+: " + DoubleToString(g_currentDIPlus, 1) + 
                    " | DI-: " + DoubleToString(g_currentDIMinus, 1);
   color adxColor = PanelColor;
   if(g_currentADX >= ADX_Strong)
      adxColor = clrGreen;
   else if(g_currentADX >= ADX_Threshold)
      adxColor = clrDarkOrange;
   else
      adxColor = clrRed;
   ObjectSetString(0, g_panelName + "_adx", OBJPROP_TEXT, adxText);
   ObjectSetInteger(0, g_panelName + "_adx", OBJPROP_COLOR, adxColor);
   
   // === ATR / VOLATILITÉ ===
   string atrText = "Volatilité: ";
   color atrColor = PanelColor;
   if(g_averageATR > 0)
   {
      double ratio = g_currentATR / g_averageATR;
      if(ratio < ATR_Min_Multiplier)
      {
         atrText += "TROP CALME 💤 (" + DoubleToString(ratio * 100, 0) + "%)";
         atrColor = clrRed;
      }
      else if(ratio < 0.7)
      {
         atrText += "Faible (" + DoubleToString(ratio * 100, 0) + "%)";
         atrColor = clrDarkOrange;
      }
      else
      {
         atrText += "OK (" + DoubleToString(ratio * 100, 0) + "%)";
         atrColor = clrGreen;
      }
   }
   else
   {
      atrText += "Calcul...";
   }
   ObjectSetString(0, g_panelName + "_atr", OBJPROP_TEXT, atrText);
   ObjectSetInteger(0, g_panelName + "_atr", OBJPROP_COLOR, atrColor);
   
   // === RSI ===
   string rsiText = "RSI M5: " + DoubleToString(g_currentRSI, 1);
   color rsiColor = PanelColor;
   if(g_currentRSI <= RSI_Oversold)
   {
      rsiText += " (PULLBACK ZONE 🔥)";
      rsiColor = clrGreen;
   }
   else if(g_currentRSI >= RSI_Overbought)
   {
      rsiText += " (PULLBACK ZONE 🔥)";
      rsiColor = clrRed;
   }
   else if(g_currentRSI < 50)
   {
      rsiText += " (zone basse)";
      rsiColor = clrDarkOrange;
   }
   else if(g_currentRSI > 50)
   {
      rsiText += " (zone haute)";
      rsiColor = clrDarkOrange;
   }
   else
   {
      rsiText += " (neutre)";
   }
   ObjectSetString(0, g_panelName + "_rsi", OBJPROP_TEXT, rsiText);
   ObjectSetInteger(0, g_panelName + "_rsi", OBJPROP_COLOR, rsiColor);
   
   // === ÉTAT ===
   string stateText = "État: ";
   color stateColor = PanelColor;
   
   if(g_inPosition)
   {
      string confText = (g_lastConfidence == CONFIDENCE_HIGH) ? " ⭐" : "";
      if(g_positionType == SIGNAL_BUY)
      {
         stateText += "EN POSITION BUY 🟢" + confText;
         stateColor = clrGreen;
      }
      else
      {
         stateText += "EN POSITION SELL 🔴" + confText;
         stateColor = clrRed;
      }
   }
   else
   {
      stateText += "En attente de signal ⏳";
      stateColor = clrDarkOrange;
   }
   ObjectSetString(0, g_panelName + "_state", OBJPROP_TEXT, stateText);
   ObjectSetInteger(0, g_panelName + "_state", OBJPROP_COLOR, stateColor);
   
   // === SPREAD ===
   long spread = SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);
   string spreadText = "Spread: " + IntegerToString(spread) + " pts";
   color spreadColor = PanelColor;
   if(spread > MaxSpreadPoints)
   {
      spreadText += " ⛔ TROP ÉLEVÉ";
      spreadColor = clrRed;
   }
   else if(spread > MaxSpreadPoints * 0.7)
   {
      spreadText += " ⚠️";
      spreadColor = clrDarkOrange;
   }
   else
   {
      spreadText += " ✅";
      spreadColor = clrGreen;
   }
   ObjectSetString(0, g_panelName + "_spread", OBJPROP_TEXT, spreadText);
   ObjectSetInteger(0, g_panelName + "_spread", OBJPROP_COLOR, spreadColor);
   
   // === FILTRE HORAIRE ===
   string timeText = "Heures: ";
   color timeColor = PanelColor;
   if(IsTimeAllowed())
   {
      timeText += "ACTIF ✅";
      timeColor = clrGreen;
   }
   else
   {
      timeText += "INACTIF ❌";
      timeColor = clrRed;
   }
   ObjectSetString(0, g_panelName + "_time", OBJPROP_TEXT, timeText);
   ObjectSetInteger(0, g_panelName + "_time", OBJPROP_COLOR, timeColor);
   
   // === MODE ===
   string modeText = HighConfidenceOnly ? "Mode: HIGH ONLY ⭐" : "Mode: TOUS signaux";
   ObjectSetString(0, g_panelName + "_mode", OBJPROP_TEXT, modeText);
   ObjectSetInteger(0, g_panelName + "_mode", OBJPROP_COLOR, PanelColor);
   
   // === AUTO-TRADE ===
   string autoText = "Auto: ";
   if(EnableAutoTrading)
   {
      autoText += "ACTIF " + DoubleToString(LotSize, 2) + " lots";
      if(g_inPosition && HasOpenPosition())
         autoText += " (EN TRADE)";
   }
   else
      autoText += "Désactivé (notifs only)";
   ObjectSetString(0, g_panelName + "_autotrade", OBJPROP_TEXT, autoText);
   ObjectSetInteger(0, g_panelName + "_autotrade", OBJPROP_COLOR, EnableAutoTrading ? clrGreen : PanelColor);
   
   // === FILTRE NEWS ===
   string newsText = "News: ";
   color newsColor = PanelColor;
   if(!FilterHighImpactNews)
   {
      newsText += "Filtre désactivé";
      newsColor = clrGray;
   }
   else if(IsHighImpactNewsNear())
   {
      newsText += "⚠️ NEWS PROCHE";
      newsColor = clrRed;
   }
   else
   {
      newsText += "OK ✅";
      newsColor = clrGreen;
   }
   ObjectSetString(0, g_panelName + "_news", OBJPROP_TEXT, newsText);
   ObjectSetInteger(0, g_panelName + "_news", OBJPROP_COLOR, newsColor);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Détection automatique GMT broker                                 |
//+------------------------------------------------------------------+
int DetectBrokerGMTOffset()
{
   if(BrokerGMTOffset != 0)
      return BrokerGMTOffset;
   
   datetime brokerTime = TimeCurrent();
   datetime gmtTime = TimeGMT();
   int diffSeconds = (int)(brokerTime - gmtTime);
   int diffHours = diffSeconds / 3600;
   
   return diffHours;
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
                         IntegerToString((long)g_lastSignalTime) + "|" +
                         IntegerToString(0) + "|" +  // placeholder pour compat ancien format
                         DoubleToString(g_entryPrice, 8) + "|" +
                         IntegerToString(g_breakevenApplied ? 1 : 0) + "|" +
                         IntegerToString((long)g_entryTime);
      
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
   if(!FileIsExist(g_stateFileName))
   {
      Print("📄 Pas d'état précédent - Démarrage frais");
      return;
   }
   
   int fileHandle = FileOpen(g_stateFileName, FILE_READ|FILE_TXT);
   
   if(fileHandle != INVALID_HANDLE)
   {
      string stateData = FileReadString(fileHandle);
      FileClose(fileHandle);
      
      string parts[];
      int count = StringSplit(stateData, '|', parts);
      
      if(count >= 3)
      {
         g_inPosition = (StringToInteger(parts[0]) == 1);
         g_positionType = (SIGNAL_TYPE)StringToInteger(parts[1]);
         g_currentTrend = (TREND_TYPE)StringToInteger(parts[2]);
         
         if(count >= 4)
            g_lastConfidence = (SIGNAL_CONFIDENCE)StringToInteger(parts[3]);
         if(count >= 5)
            g_lastSignalTime = (datetime)StringToInteger(parts[4]);
         // position 5 = placeholder (ancien emaCrossCount, supprimé v4.8)
         if(count >= 7)
            g_entryPrice = StringToDouble(parts[6]);
         if(count >= 8)
            g_breakevenApplied = (StringToInteger(parts[7]) == 1);
         if(count >= 9)
            g_entryTime = (datetime)StringToInteger(parts[8]);
         
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
//| Réinitialiser état                                               |
//+------------------------------------------------------------------+
void ResetState()
{
   g_inPosition = false;
   g_positionType = SIGNAL_NONE;
   g_lastSignal = SIGNAL_NONE;
   g_lastConfidence = CONFIDENCE_NONE;
   g_lastSignalTime = 0;
   g_entryPrice = 0;
   g_entryTime = 0;
   g_breakevenApplied = false;
   
   if(FileIsExist(g_stateFileName))
      FileDelete(g_stateFileName);
   
   Print("🔄 État réinitialisé");
}

//+------------------------------------------------------------------+
//| Mise à jour RSI pour panneau (même hors horaires)                |
//+------------------------------------------------------------------+
void UpdateRSI()
{
   double rsiValues[];
   ArraySetAsSeries(rsiValues, true);
   if(CopyBuffer(g_rsiM5Handle, 0, 0, 2, rsiValues) >= 2)
      g_currentRSI = rsiValues[1];
}

//+------------------------------------------------------------------+
//| TRAILING STOP + AUTO BREAKEVEN                                   |
//| Suit le prix pour maximiser les gains                            |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!EnableAutoTrading) return;
   if(!EnableTrailingStop && !EnableAutoBreakeven) return;
   if(g_currentATR <= 0) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      double currentSL = PositionGetDouble(POSITION_SL);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
      
      // Utiliser le prix d'entrée sauvegardé (plus fiable)
      if(g_entryPrice <= 0) g_entryPrice = openPrice;
      
      double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
      
      // === POSITION BUY ===
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         double profit = bid - g_entryPrice;
         
         // 1. AUTO BREAKEVEN : quand profit >= BreakevenATR → SL = entry + 1 point
         if(EnableAutoBreakeven && !g_breakevenApplied)
         {
            double beDistance = g_currentATR * BreakevenATRMultiplier;
            if(profit >= beDistance)
            {
               double newSL = NormalizeDouble(g_entryPrice + point, digits);
               if(currentSL < newSL || currentSL == 0)
               {
                  if(g_trade.PositionModify(ticket, newSL, 0))
                  {
                     g_breakevenApplied = true;
                     Print("🛡️ BREAKEVEN APPLIQUÉ! SL déplacé à ", DoubleToString(newSL, digits));
                     if(EnableNotifications)
                        SendNotification("🛡️ BREAKEVEN: " + g_displayName + " | Perte impossible!");
                     SaveState();
                  }
               }
            }
         }
         
         // 2. TRAILING STOP : suit le prix à distance TrailingATR
         if(EnableTrailingStop && g_breakevenApplied)
         {
            double trailDistance = g_currentATR * TrailingATRMultiplier;
            double newSL = NormalizeDouble(bid - trailDistance, digits);
            
            // Minimum 1 pip de mouvement pour limiter les requêtes broker
            double minStep = point * 10;
            if(newSL > currentSL + minStep && newSL > g_entryPrice)
            {
               if(g_trade.PositionModify(ticket, newSL, 0))
               {
                  Print("📈 TRAILING STOP BUY: SL → ", DoubleToString(newSL, digits),
                        " | Profit protégé: ", DoubleToString((newSL - g_entryPrice) / point, 0), " pts");
               }
            }
         }
      }
      
      // === POSITION SELL ===
      else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      {
         double profit = g_entryPrice - ask;
         
         // 1. AUTO BREAKEVEN
         if(EnableAutoBreakeven && !g_breakevenApplied)
         {
            double beDistance = g_currentATR * BreakevenATRMultiplier;
            if(profit >= beDistance)
            {
               double newSL = NormalizeDouble(g_entryPrice - point, digits);
               if(currentSL > newSL || currentSL == 0)
               {
                  if(g_trade.PositionModify(ticket, newSL, 0))
                  {
                     g_breakevenApplied = true;
                     Print("🛡️ BREAKEVEN APPLIQUÉ! SL déplacé à ", DoubleToString(newSL, digits));
                     if(EnableNotifications)
                        SendNotification("🛡️ BREAKEVEN: " + g_displayName + " | Perte impossible!");
                     SaveState();
                  }
               }
            }
         }
         
         // 2. TRAILING STOP
         if(EnableTrailingStop && g_breakevenApplied)
         {
            double trailDistance = g_currentATR * TrailingATRMultiplier;
            double newSL = NormalizeDouble(ask + trailDistance, digits);
            
            // Minimum 1 pip de mouvement pour limiter les requêtes broker
            double minStep = point * 10;
            if((newSL < currentSL - minStep || currentSL == 0) && newSL < g_entryPrice)
            {
               if(g_trade.PositionModify(ticket, newSL, 0))
               {
                  Print("📉 TRAILING STOP SELL: SL → ", DoubleToString(newSL, digits),
                        " | Profit protégé: ", DoubleToString((g_entryPrice - newSL) / point, 0), " pts");
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| AUTO-TRADING: Ouvrir une position                                |
//+------------------------------------------------------------------+
bool OpenPosition(SIGNAL_TYPE signal)
{
   if(!EnableAutoTrading) return false;
   if(HasAnyAccountPosition())
   {
      Print("⚠️ Position déjà ouverte sur le compte - pas de doublon");
      return false;
   }
   
   // Vérifier que le trading auto est autorisé dans MT5
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("❌ Auto-trading désactivé dans MT5! Active 'Algo Trading' dans la barre d'outils");
      return false;
   }
   
   // Calculer Stop Loss basé sur ATR H1
   double sl = 0;
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   
   if(UseStopLoss && g_currentATR > 0)
   {
      double slDistance = g_currentATR * StopLossATRMultiplier;
      
      if(signal == SIGNAL_BUY)
         sl = NormalizeDouble(SymbolInfoDouble(g_symbol, SYMBOL_ASK) - slDistance, digits);
      else
         sl = NormalizeDouble(SymbolInfoDouble(g_symbol, SYMBOL_BID) + slDistance, digits);
   }
   
   bool result = false;
   
   if(signal == SIGNAL_BUY)
      result = g_trade.Buy(LotSize, g_symbol, 0, sl, 0, "SwiftReaper PRO");
   else
      result = g_trade.Sell(LotSize, g_symbol, 0, sl, 0, "SwiftReaper PRO");
   
   if(result)
   {
      string direction = (signal == SIGNAL_BUY) ? "BUY" : "SELL";
      string slText = (sl > 0) ? " | SL: " + DoubleToString(sl, digits) : " | SL: Aucun";
      Print("✅ Position ouverte: ", direction, " ", DoubleToString(LotSize, 2), " lots", slText);
      
      if(EnableNotifications)
         SendNotification("🤖 AUTO-TRADE: " + direction + " " + g_displayName + " " + DoubleToString(LotSize, 2) + " lots");
   }
   else
   {
      Print("❌ Erreur ouverture position: ", g_trade.ResultRetcodeDescription());
      if(EnableNotifications)
         SendNotification("❌ ERREUR AUTO-TRADE: " + g_trade.ResultRetcodeDescription());
   }
   return result;
}

//+------------------------------------------------------------------+
//| AUTO-TRADING: Fermer la position                                 |
//+------------------------------------------------------------------+
void ClosePosition()
{
   if(!EnableAutoTrading) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == g_symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            // Lire le profit AVANT de fermer (sinon = 0)
            double profit = PositionGetDouble(POSITION_PROFIT);
            
            if(g_trade.PositionClose(ticket))
            {
               Print("✅ Position fermée | P&L: ", DoubleToString(profit, 2));
               
               if(EnableNotifications)
               {
                  string profitText = (profit >= 0) ? "🟢 +" : "🔴 ";
                  SendNotification("🤖 AUTO-CLOSE: " + g_displayName + " | " + profitText + DoubleToString(profit, 2));
               }
            }
            else
            {
               Print("❌ Erreur fermeture: ", g_trade.ResultRetcodeDescription());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| AUTO-TRADING: Vérifier si position ouverte                       |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   if(!EnableAutoTrading) return false;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == g_symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Vérifier si une position existe SUR TOUT LE COMPTE               |
//| (n'importe quelle paire, n'importe quel magic)                   |
//| → Pot de paris: 1 seule position à la fois, point final          |
//+------------------------------------------------------------------+
bool HasAnyAccountPosition()
{
   return (PositionsTotal() > 0);
}
//+------------------------------------------------------------------+
