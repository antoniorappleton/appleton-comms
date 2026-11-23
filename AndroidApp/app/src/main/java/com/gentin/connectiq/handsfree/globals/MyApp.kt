package com.gentin.connectiq.handsfree.globals

import android.content.Context
import com.garmin.android.connectiq.IQApp
import com.gentin.connectiq.handsfree.helpers.isRunningInEmulator

val simApp = IQApp("")
private val prodApp = IQApp("76526066-d191-46f4-9cfb-bbf9ed955b23", "Handsfree", 0)
private val betaApp = IQApp("15e9d7bf-a94e-4e86-adf4-92adf1b3e651", "Appleton Comms", 0)
private val prodWidget = IQApp("4241a52e-81db-4356-ac43-c8dfeb7d0be0", "Handsfree", 0)
private val betaWidget = IQApp("cdc225d9-bc88-4d9e-a8a6-ce7dffdd0714", "Handsfree-B", 0)

fun storeID(app: IQApp): String? {
    return when (app) {
        prodApp -> "73107243-f322-4cf2-bb3d-78f2a4ee8920"
        prodWidget -> "629f3ba5-66bc-4b44-a078-3365a85212f8"
        betaApp -> "be1284eb-7487-4547-8518-09fe53726510"
        betaWidget -> "a9a847b7-d15f-493d-8242-efadbdd9cdf2"
        else -> null
    }
}

fun defaultApp(context: Context): IQApp {
    return if (isRunningInEmulator(context)) {
        simApp
    } else {
        betaApp
    }
}

fun watchApps(context: Context) = if (isRunningInEmulator(context)) {
    listOf(simApp)
} else {
    // Only the Appleton Comms watch app is trusted: the other IDs belong to the upstream
    // Handsfree developer and must not be able to drive calls or text messages here.
    listOf(betaApp)
}

fun appLogName(app: IQApp): String {
    return when (app) {
        simApp -> "sim"
        prodApp -> "prod-a"
        betaApp -> "beta-a"
        prodWidget -> "prod-w"
        betaWidget -> "beta-w"
        else -> "unknown(${app.applicationId})"
    }
}
