//+------------------------------------------------------------------+

//|                                               RecoveryMode.mqh   |

//|            Omni-B3 EA v2.60 — Modo de Recuperação                 |

//|    Altera comportamento da grade quando DD está alto              |

//+------------------------------------------------------------------+

//| Copyright 2026, Projeto Omni-B3                                 |

//| https://github.com/helveciopereira/Stocks                        |

//+------------------------------------------------------------------+

#property copyright "Projeto Omni-B3"

#property link      "https://github.com/helveciopereira/Stocks"

#property version   "2.50"

#property strict

#include "Defines.mqh"

#include "Logger.mqh"

//+------------------------------------------------------------------+

//| Modo de Recuperação Automática                                    |

//|                                                                   |

//| Inspirado no "RECOVERY" do ToTheMoon v3.5:                        |

//| Quando o drawdown da grade ultrapassa um limite (% ou quantidade  |

//| de ordens), o EA entra em modo recovery alterando:                |

//| - Modo de fechamento (para um mais agressivo)                    |

//| - Passo da grid (pode adicionar espaçamento extra)               |

//| - Multiplicador de lote (pode aumentar próximo lote)             |

//| - TakeProfit (pode ser reduzido para sair mais rápido)           |

//|                                                                   |

//| O modo recovery TRAVA — não sai até fechamento completo ou       |

//| reset manual, evitando que o EA fique alternando entre modos.    |

//+------------------------------------------------------------------+

class CRecoveryMode {

private:

    CLogger *m_logger;

    // Gatilhos para ativar recovery

    double   m_dd_trigger;          // DD% para ativar (ex: 50.0 = 50%)

    int      m_order_count_trigger; // Qtde ordens para ativar (0 = desabilitado)

    bool     m_lock_mode;           // Se deve travar em recovery até reset

    // Ajustes do modo recovery

    ENUM_CLOSE_MODE m_recovery_close_mode;  // Modo de fechamento em recovery

    int      m_extra_step_points;   // Pontos extras no passo da grid

    double   m_extra_lot_factor;    // Fator extra no multiplicador de lote

    int      m_recovery_tp;         // TakeProfit em recovery (pontos)

    // Estado

    bool     m_is_active;           // Se recovery está ativo

    datetime m_activation_time;     // Quando foi ativado

    int      m_activation_count;    // Quantas vezes ativou (sessão)

public:

    //+--------------------------------------------------------------+

    //| Construtor                                                    |

    //+--------------------------------------------------------------+

    CRecoveryMode(CLogger *logger) {

        m_logger = logger;

        // Defaults — recovery conservador

        m_dd_trigger           = 100.0;       // 100% = nunca ativa por DD

        m_order_count_trigger  = 0;           // 0 = desabilitado por ordens

        m_lock_mode            = false;

        m_recovery_close_mode  = CMODE_ACCEPT_LOSS;

        m_extra_step_points    = 0;

        m_extra_lot_factor     = 0.0;

        m_recovery_tp          = 100;

        m_is_active            = false;

        m_activation_time      = 0;

        m_activation_count     = 0;

    }

    //+--------------------------------------------------------------+

    //| Configura gatilhos de ativação                                |

    //+--------------------------------------------------------------+

    void SetTriggers(double dd_percent, int order_count, bool lock) {

        m_dd_trigger = dd_percent;

        m_order_count_trigger = order_count;

        m_lock_mode = lock;

        m_logger.Info("Recovery",

            StringFormat("Gatilhos: DD=%.0f%% | Ordens=%d | Travar=%s",

                         m_dd_trigger, m_order_count_trigger,

                         m_lock_mode ? "Sim" : "Não"));

    }

    //+--------------------------------------------------------------+

    //| Configura ajustes do modo recovery                           |

    //+--------------------------------------------------------------+

    void SetRecoveryParams(ENUM_CLOSE_MODE close_mode, int extra_step,

                           double extra_lot, int tp_points) {

        m_recovery_close_mode = close_mode;

        m_extra_step_points = extra_step;

        m_extra_lot_factor = extra_lot;

        m_recovery_tp = tp_points;

        m_logger.Info("Recovery",

            StringFormat("Params: Fechamento=%s | +Passo=%d | +Lote=%.2f | TP=%d",

                         EnumToString(close_mode), extra_step, extra_lot, tp_points));

    }

    //+--------------------------------------------------------------+

    //| Verifica se deve ativar/desativar recovery                   |

    //| dd_percent: drawdown atual da grade em %                     |

    //| order_count: quantidade atual de ordens/níveis               |

    //+--------------------------------------------------------------+

    void Evaluate(double dd_percent, int order_count) {

        if(m_is_active) {

            // Recovery já ativo — verifica se pode desativar

            if(!m_lock_mode) {

                bool below_dd = (dd_percent < m_dd_trigger * 0.5);  // Metade do gatilho

                bool below_orders = (m_order_count_trigger == 0 ||

                                     order_count < m_order_count_trigger / 2);

                if(below_dd && below_orders) {

                    Deactivate();

                }

            }

            // Se lock_mode = true, só sai via Reset() manual ou ClearAllLevels()

            return;

        }

        // Verifica se deve ativar

        bool dd_trigger = (m_dd_trigger < 100.0 && dd_percent >= m_dd_trigger);

        bool order_trigger = (m_order_count_trigger > 0 &&

                              order_count >= m_order_count_trigger);

        if(dd_trigger || order_trigger) {

            Activate(dd_percent, order_count);

        }

    }

    //+--------------------------------------------------------------+

    //| Ativa o modo recovery                                        |

    //+--------------------------------------------------------------+

    void Activate(double dd_pct, int orders) {

        m_is_active = true;

        m_activation_time = TimeCurrent();

        m_activation_count++;

        m_logger.Warning("Recovery",

            StringFormat("âš ï¸? RECOVERY ATIVADO! DD=%.1f%% Ordens=%d (ativação #%d)",

                         dd_pct, orders, m_activation_count));

    }

    //+--------------------------------------------------------------+

    //| Desativa o modo recovery                                      |

    //+--------------------------------------------------------------+

    void Deactivate() {

        if(!m_is_active) return;

        m_is_active = false;

        int duration = (int)(TimeCurrent() - m_activation_time);

        m_logger.Info("Recovery",

            StringFormat("[OK] Recovery desativado após %d segundos", duration));

    }

    //+--------------------------------------------------------------+

    //| Reset manual do recovery (botão ou fechamento total)         |

    //+--------------------------------------------------------------+

    void Reset() {

        m_is_active = false;

        m_logger.Info("Recovery", "Recovery resetado manualmente");

    }

    //+--------------------------------------------------------------+

    //| Getters — verificam se estamos em recovery e obtém ajustes   |

    //+--------------------------------------------------------------+

    bool IsActive()                      { return m_is_active; }

    ENUM_CLOSE_MODE GetCloseMode()       { return m_recovery_close_mode; }

    int  GetExtraStepPoints()            { return m_extra_step_points; }

    double GetExtraLotFactor()           { return m_extra_lot_factor; }

    int  GetRecoveryTP()                 { return m_recovery_tp; }

    int  GetActivationCount()            { return m_activation_count; }

    //+--------------------------------------------------------------+

    //| Status para dashboard/log                                     |

    //+--------------------------------------------------------------+

    string GetStatusString() {

        if(!m_is_active) return "Recovery:  Inativo";

        int elapsed = (int)(TimeCurrent() - m_activation_time);

        return StringFormat("Recovery: âš ï¸? ATIVO há %dm | #%d",

                           elapsed / 60, m_activation_count);

    }

};

//+------------------------------------------------------------------+

