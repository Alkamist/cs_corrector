package main

Parameter :: enum {
    Legato_First_Note_Delay,
    Legato_Portamento_Delay,
    Legato_Slow_Delay,
    Legato_Medium_Delay,
    Legato_Fast_Delay,
}

parameter_info := [len(Parameter)]Parameter_Info{
    {
        id = .Legato_First_Note_Delay,
        flags = {.Is_Automatable},
        name = "Legato First Note Delay",
        module = "",
        min_value = -500.0,
        max_value = 500.0,
        default_value = -60.0,
    }, {
        id = .Legato_Portamento_Delay,
        flags = {.Is_Automatable},
        name = "Legato Portamento Delay",
        module = "",
        min_value = -500.0,
        max_value = 500.0,
        default_value = -300.0,
    }, {
        id = .Legato_Slow_Delay,
        flags = {.Is_Automatable},
        name = "Legato Slow Delay",
        module = "",
        min_value = -500.0,
        max_value = 500.0,
        default_value = -300.0,
    }, {
        id = .Legato_Medium_Delay,
        flags = {.Is_Automatable},
        name = "Legato Medium Delay",
        module = "",
        min_value = -500.0,
        max_value = 500.0,
        default_value = -300.0,
    }, {
        id = .Legato_Fast_Delay,
        flags = {.Is_Automatable},
        name = "Legato Fast Delay",
        module = "",
        min_value = -500.0,
        max_value = 500.0,
        default_value = -150.0,
    },
}