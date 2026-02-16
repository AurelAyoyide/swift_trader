//+------------------------------------------------------------------+
//|                                               SwiftTrader_v1.3.mq5 |
//|                        Copyright 2025, SwiftTrader Development    |
//|                                     https://www.swifttrader.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, SwiftTrader Development"
#property link      "https://www.swifttrader.com"
#property version   "1.30"
#property description "Swift Trader v1.3 - Détection de tendance & exécution multi-timeframe"
#property strict

// Enum pour les tendances de marché
enum TREND_TYPE
{
   TREND_NONE,    // Tendance neutre
   TREND_BULLISH, // Tendance haussière
   TREND_BEARISH, // Tendance baissière
   TREND_RANGE    // Tendance en range
};

// Enum pour les types de signaux
enum SIGNAL_TYPE
{
   SIGNAL_NONE,   // Aucun signal
   SIGNAL_BUY,    // Signal d'achat
   SIGNAL_SELL    // Signal de vente
};

// Paramètres d'entrée
input bool     EnableNotifications = true;      // Activer les notifications
input double   ADXThreshold = 25;               // Seuil ADX pour validation de tendance
input int      EMAFast_H1 = 20;                 // EMA rapide pour H1
input int      EMASlow_H1 = 50;                 // EMA lente pour H1
input int      EMAFast_M5 = 10;                 // EMA rapide pour M5
input int      EMASlow_M5 = 21;                 // EMA lente pour M5
input int      ADX_Period = 14;                 // Période ADX
input string   UpdateFrequency_H1 = "1h";       // Fréquence de mise à jour de tendance H1

// Variables globales
TREND_TYPE currentTrend = TREND_NONE;           // Tendance actuelle
SIGNAL_TYPE lastSignal = SIGNAL_NONE;           // Dernier signal généré
bool positionOpen = false;                      // État de la position (ouverte/fermée)
string currentSymbol;                           // Symbole actuel
datetime lastCheck = 0;                         // Dernière vérification de tendance H1
datetime lastSignalTime = 0;                    // Horodatage du dernier signal
datetime last_processed_h1_candle = 0;          // Dernière bougie H1 traitée
datetime last_processed_m5_candle = 0;          // Dernière bougie M5 traitée

// Handles des indicateurs
int h1_ema_fast_handle;
int h1_ema_slow_handle;
int h1_adx_handle;
int m5_ema_fast_handle;
int m5_ema_slow_handle;

// Structure pour stocker les propriétés du panneau de contrôle
struct ControlPanel
{
   string name;
   int x;
   int y;
   int width;
   int height;
   color backgroundColor;
   color textColor;
   int fontSize;
};

ControlPanel panel;

// Noms des objets texte dans le panneau
string titleObj = "SwiftTraderTitle";
string trendObj = "SwiftTraderTrend";
string signalObj = "SwiftTraderSignal";
string positionObj = "SwiftTraderPosition";
string adxObj = "SwiftTraderADX";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialisation du symbole courant
    currentSymbol = Symbol();
    
    // Initialisation des handles des indicateurs H1
    h1_ema_fast_handle = iMA(currentSymbol, PERIOD_H1, EMAFast_H1, 0, MODE_EMA, PRICE_CLOSE);
    h1_ema_slow_handle = iMA(currentSymbol, PERIOD_H1, EMASlow_H1, 0, MODE_EMA, PRICE_CLOSE);
    h1_adx_handle = iADX(currentSymbol, PERIOD_H1, ADX_Period);
    
    // Initialisation des handles des indicateurs M5
    m5_ema_fast_handle = iMA(currentSymbol, PERIOD_M5, EMAFast_M5, 0, MODE_EMA, PRICE_CLOSE);
    m5_ema_slow_handle = iMA(currentSymbol, PERIOD_M5, EMASlow_M5, 0, MODE_EMA, PRICE_CLOSE);

    // Vérification des handles
    if(h1_ema_fast_handle == INVALID_HANDLE || h1_ema_slow_handle == INVALID_HANDLE || 
       h1_adx_handle == INVALID_HANDLE || m5_ema_fast_handle == INVALID_HANDLE || 
       m5_ema_slow_handle == INVALID_HANDLE)
    {
        Print("Erreur lors de la création des indicateurs");
        return INIT_FAILED;
    }
    
    // Initialisation du panneau de contrôle
    panel.name = "SwiftTraderPanel";
    panel.x = 20;
    panel.y = 20;
    panel.width = 300;
    panel.height = 130;
    panel.backgroundColor = clrWhite;
    panel.textColor = clrBlack;
    panel.fontSize = 10;
    
    // Création du panneau de contrôle
    CreatePanel();
    
    // Détection initiale de la tendance
    DetectH1Trend();
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Libération des handles des indicateurs
    IndicatorRelease(h1_ema_fast_handle);
    IndicatorRelease(h1_ema_slow_handle);
    IndicatorRelease(h1_adx_handle);
    IndicatorRelease(m5_ema_fast_handle);
    IndicatorRelease(m5_ema_slow_handle);
    
    // Suppression du panneau de contrôle et des textes
    ObjectDelete(0, panel.name);
    ObjectDelete(0, titleObj);
    ObjectDelete(0, trendObj);
    ObjectDelete(0, signalObj);
    ObjectDelete(0, positionObj);
    ObjectDelete(0, adxObj);
    
    Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Vérification de nouvelles bougies complètes pour H1 et M5
    CheckForNewCandles();
    
    // Mise à jour du panneau de contrôle à chaque tick
    UpdatePanel();
}

//+------------------------------------------------------------------+
//| Fonction de vérification des nouvelles bougies                   |
//+------------------------------------------------------------------+
void CheckForNewCandles()
{
    // Récupération des heures des bougies H1 et M5
    datetime h1_candle_time[2];
    datetime m5_candle_time[2];
    
    CopyTime(currentSymbol, PERIOD_H1, 0, 2, h1_candle_time);
    CopyTime(currentSymbol, PERIOD_M5, 0, 2, m5_candle_time);
    
    // Vérification d'une nouvelle bougie H1 fermée
    if(h1_candle_time[1] > last_processed_h1_candle)
    {
        DetectH1Trend();
        last_processed_h1_candle = h1_candle_time[1];
    }
    
    // Vérification d'une nouvelle bougie M5 fermée
    if(m5_candle_time[1] > last_processed_m5_candle)
    {
        CheckM5Signals();
        last_processed_m5_candle = m5_candle_time[1];
    }
}

//+------------------------------------------------------------------+
//| Fonction de détection de tendance H1                             |
//+------------------------------------------------------------------+
void DetectH1Trend()
{
    // Récupération des valeurs des indicateurs
    double ema_fast_values[];
    double ema_slow_values[];
    double adx_values[];
    double adx_di_plus[];  // +DI
    double adx_di_minus[]; // -DI
    
    // Allocation des tableaux
    ArraySetAsSeries(ema_fast_values, true);
    ArraySetAsSeries(ema_slow_values, true);
    ArraySetAsSeries(adx_values, true);
    ArraySetAsSeries(adx_di_plus, true);
    ArraySetAsSeries(adx_di_minus, true);
    
    // Copie des données des indicateurs (utilisation des bougies fermées)
    CopyBuffer(h1_ema_fast_handle, 0, 0, 4, ema_fast_values);
    CopyBuffer(h1_ema_slow_handle, 0, 0, 4, ema_slow_values);
    CopyBuffer(h1_adx_handle, 0, 0, 4, adx_values);
    CopyBuffer(h1_adx_handle, 1, 0, 4, adx_di_plus);   // +DI est buffer 1
    CopyBuffer(h1_adx_handle, 2, 0, 4, adx_di_minus);  // -DI est buffer 2
    
    // Travailler avec des bougies fermées (indice 1)
    bool current_ema_bullish = ema_fast_values[1] > ema_slow_values[1];
    bool previous_ema_bullish = ema_fast_values[2] > ema_slow_values[2];
    double current_adx = adx_values[1];
    double current_di_plus = adx_di_plus[1];
    double current_di_minus = adx_di_minus[1];
    
    // Détection du croisement sur bougies fermées
    bool ema_cross_up = !previous_ema_bullish && current_ema_bullish;
    bool ema_cross_down = previous_ema_bullish && !current_ema_bullish;
    
    // Détection de la tendance
    TREND_TYPE previous_trend = currentTrend;
    
    // Si ADX faible, c'est un range
    if(current_adx < ADXThreshold)
    {
        currentTrend = TREND_RANGE;
        if(previous_trend != TREND_RANGE)
        {
            Print("Nouvelle tendance H1 détectée : RANGE (ADX = ", DoubleToString(current_adx, 1), ")");
        }
    }
    // Sinon vérifier les croisements et la direction
    else if(ema_cross_up || (current_ema_bullish && current_di_plus > current_di_minus))
    {
        currentTrend = TREND_BULLISH;
        if(previous_trend != TREND_BULLISH)
        {
            Print("Nouvelle tendance H1 détectée : HAUSSIÈRE (ADX = ", DoubleToString(current_adx, 1), ")");
        }
    }
    else if(ema_cross_down || (!current_ema_bullish && current_di_minus > current_di_plus))
    {
        currentTrend = TREND_BEARISH;
        if(previous_trend != TREND_BEARISH)
        {
            Print("Nouvelle tendance H1 détectée : BAISSIÈRE (ADX = ", DoubleToString(current_adx, 1), ")");
        }
    }
    
    // Si c'est la première exécution et aucune tendance n'est encore définie
    if(previous_trend == TREND_NONE && currentTrend == TREND_NONE)
    {
        if(current_adx < ADXThreshold)
        {
            currentTrend = TREND_RANGE;
            Print("Tendance H1 initiale : RANGE (ADX = ", DoubleToString(current_adx, 1), ")");
        }
        else if(current_ema_bullish)
        {
            currentTrend = TREND_BULLISH;
            Print("Tendance H1 initiale : HAUSSIÈRE (ADX = ", DoubleToString(current_adx, 1), ")");
        }
        else
        {
            currentTrend = TREND_BEARISH;
            Print("Tendance H1 initiale : BAISSIÈRE (ADX = ", DoubleToString(current_adx, 1), ")");
        }
    }
}

//+------------------------------------------------------------------+
//| Fonction de vérification des signaux M5                          |
//+------------------------------------------------------------------+
void CheckM5Signals()
{
    // Si la tendance est en range, pas de signal
    if(currentTrend == TREND_RANGE || currentTrend == TREND_NONE)
        return;
        
    // Récupération des valeurs des EMA M5
    double ema_fast_m5_values[];
    double ema_slow_m5_values[];
    
    // Allocation des tableaux
    ArraySetAsSeries(ema_fast_m5_values, true);
    ArraySetAsSeries(ema_slow_m5_values, true);
    
    // Copie des données des indicateurs (utilisation des bougies fermées)
    CopyBuffer(m5_ema_fast_handle, 0, 0, 4, ema_fast_m5_values);
    CopyBuffer(m5_ema_slow_handle, 0, 0, 4, ema_slow_m5_values);
    
    // Vérification du croisement sur des bougies fermées
    bool cross_up = ema_fast_m5_values[1] > ema_slow_m5_values[1] && ema_fast_m5_values[2] <= ema_slow_m5_values[2];
    bool cross_down = ema_fast_m5_values[1] < ema_slow_m5_values[1] && ema_fast_m5_values[2] >= ema_slow_m5_values[2];
    
    // Récupération de l'heure actuelle
    datetime currentTime = TimeCurrent();
    
    // Vérification si un signal d'achat doit être généré
    if(currentTrend == TREND_BULLISH && cross_up && !positionOpen && currentTime - lastSignalTime > PeriodSeconds(PERIOD_M5))
    {
        // Signal d'achat
        lastSignal = SIGNAL_BUY;
        positionOpen = true;
        lastSignalTime = currentTime;
        
        string message = "📣 SWIFT TRADER 🔥 🚀\n" +
                         "OPEN BUY " + currentSymbol + " NOW!\n" +
                         "📈 Let's ride this wave 📊";
        Print(message);
        
        if(EnableNotifications)
            SendNotification(message);
    }
    // Vérification si un signal de vente doit être généré
    else if(currentTrend == TREND_BEARISH && cross_down && !positionOpen && currentTime - lastSignalTime > PeriodSeconds(PERIOD_M5))
    {
        // Signal de vente
        lastSignal = SIGNAL_SELL;
        positionOpen = true;
        lastSignalTime = currentTime;
        
        string message = "📣 SWIFT TRADER ⚠️ 💣\n" +
                         "OPEN SELL " + currentSymbol + " NOW!\n" +
                         "📉 Trend says go low 📊";
        Print(message);
        
        if(EnableNotifications)
            SendNotification(message);
    }
    // Vérification si un signal de clôture d'achat doit être généré
    else if(lastSignal == SIGNAL_BUY && cross_down && positionOpen && currentTime - lastSignalTime > PeriodSeconds(PERIOD_M5))
    {
        // Signal de clôture d'achat
        lastSignal = SIGNAL_NONE;
        positionOpen = false;
        lastSignalTime = currentTime;
        
        string message = "🛑 SWIFT TRADER ✅ 📤\n" +
                         "CLOSE BUY " + currentSymbol + " NOW!\n" +
                         "🔁 EMA cross-down detected 🧠";
        Print(message);
        
        if(EnableNotifications)
            SendNotification(message);
    }
    // Vérification si un signal de clôture de vente doit être généré
    else if(lastSignal == SIGNAL_SELL && cross_up && positionOpen && currentTime - lastSignalTime > PeriodSeconds(PERIOD_M5))
    {
        // Signal de clôture de vente
        lastSignal = SIGNAL_NONE;
        positionOpen = false;
        lastSignalTime = currentTime;
        
        string message = "🛑 SWIFT TRADER ✅ 📤\n" +
                         "CLOSE SELL " + currentSymbol + " NOW!\n" +
                         "🔁 EMA cross-up detected 🧠";
        Print(message);
        
        if(EnableNotifications)
            SendNotification(message);
    }
}

//+------------------------------------------------------------------+
//| Création du panneau de contrôle                                  |
//+------------------------------------------------------------------+
void CreatePanel()
{
    // Création d'un simple label pour indiquer la tendance
    if(!ObjectCreate(0, trendObj, OBJ_LABEL, 0, 0, 0))
    {
        Print("Erreur lors de la création du label de tendance");
        return;
    }
    
    // Configuration du label principal
    ObjectSetString(0, trendObj, OBJPROP_TEXT, "TENDANCE: ⌛");
    ObjectSetInteger(0, trendObj, OBJPROP_XDISTANCE, 20);
    ObjectSetInteger(0, trendObj, OBJPROP_YDISTANCE, 20);
    ObjectSetInteger(0, trendObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, trendObj, OBJPROP_FONTSIZE, 14);
    ObjectSetInteger(0, trendObj, OBJPROP_COLOR, clrBlack);
    ObjectSetString(0, trendObj, OBJPROP_FONT, "Arial Bold");
    ObjectSetInteger(0, trendObj, OBJPROP_SELECTABLE, false);

    // Forcer le rafraîchissement du graphique
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Mise à jour des informations du panneau de contrôle              |
//+------------------------------------------------------------------+
void UpdatePanel()
{
    // Mise à jour du label de tendance
    string trendText = "TENDANCE: ";
    color trendColor = clrBlack;
    
    switch(currentTrend)
    {
        case TREND_BULLISH:
            trendText += "HAUSSIÈRE";
            trendColor = clrGreen;
            break;
        case TREND_BEARISH:
            trendText += "BAISSIÈRE";
            trendColor = clrRed;
            break;
        case TREND_RANGE:
            trendText += "RANGE";
            trendColor = clrDarkOrange;
            break;
        default:
            trendText += "INCONNUE";
            trendColor = clrGray;
            break;
    }
    
    // Mise à jour du texte et de la couleur du label
    ObjectSetString(0, trendObj, OBJPROP_TEXT, trendText);
    ObjectSetInteger(0, trendObj, OBJPROP_COLOR, trendColor);
    
    // Forcer le rafraîchissement du graphique
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Fonction pour définir l'alpha (transparence) d'une couleur       |
//+------------------------------------------------------------------+
uint SetAlpha(color clr, uchar alpha)
{
    return ((uint)alpha << 24) | (clr & 0xFFFFFF);
}