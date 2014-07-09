/**
 * Copyright (C) 2011 Twilio, Inc.
 * All rights reserved.
 *
 * Brian Tarricone, 2011/11/10
 */

#if defined(PJMEDIA_AUDIO_DEV_HAS_ANDROID)

#include <pjmedia_audiodev.h>
#include <pj/log.h>
#include <pj/pool.h>

#include <stdlib.h>
#include <stdint.h>
#include <dlfcn.h>
#include <jni.h>
#include <sys/system_properties.h>

#include "android_sles_dev.h"

#define THIS_FILE "android_dev.c"

typedef int (*jni_get_created_java_vms_t)(JavaVM **, jsize, jsize *);

// fwd decl
extern pjmedia_aud_dev_factory *pjmedia_android_jni_factory(pj_pool_factory *pf,
                                                            JavaVM *jvm);

static const char *opensles_blacklist[] = {
    "bcm21553",  // e.g. samsung gt-s5360, lots of "too many objects" errors
    "goldfish",  // emulator, just doesn't work right
    "msm8660",  // pantech p4100 tablet; sound is messed up and device reboots after ~30 seconds
    "SO-01E",  // sony xperia so-o1e, often hangs app while opening audio device
    "tegra",  // nvidia tegra2, gives errors about not being able to open the device more than once
    "thunderc",  // LG LS670, reboots when opening audio device (Cabulous)
};

static pj_status_t
detect_opensles(sles_lib_ptr_table_t *ptr_table)
{
    void *dlh = NULL;
    size_t i;

    if (getenv("PJMEDIA_ANDROID_FORCE_JNI"))
        return PJ_ENOTFOUND;

    char board_platform[PROP_VALUE_MAX] = "";
    char hardware[PROP_VALUE_MAX] = "";
    char device[PROP_VALUE_MAX] = "";
    __system_property_get("ro.board.platform", board_platform);
    __system_property_get("ro.hardware", hardware);
    __system_property_get("ro.product.device", device);

    for (i = 0; i < sizeof(opensles_blacklist) / sizeof(opensles_blacklist[0]); ++i) {
        if (!strcmp(board_platform, opensles_blacklist[i]) ||
            !strcmp(hardware, opensles_blacklist[i]) ||
            !strcmp(device, opensles_blacklist[i]))
        {
            PJ_LOG(3, (THIS_FILE, "Hardware is in OpenSL ES blacklist"));
            return PJ_ENOTFOUND;
        }
    }

    pj_bzero(ptr_table, sizeof(*ptr_table));

    dlh = dlopen("/system/lib/libOpenSLES.so", RTLD_LOCAL);
    if (!dlh)
        dlh = dlopen("libOpenSLES.so", RTLD_LOCAL);

    if (dlh) {
        ptr_table->slCreateEngine = dlsym(dlh, "slCreateEngine");
        ptr_table->SL_IID_ANDROIDSIMPLEBUFFERQUEUE = dlsym(dlh, "SL_IID_ANDROIDSIMPLEBUFFERQUEUE");
        ptr_table->SL_IID_ANDROIDCONFIGURATION = dlsym(dlh, "SL_IID_ANDROIDCONFIGURATION");
        ptr_table->SL_IID_RECORD = dlsym(dlh, "SL_IID_RECORD");
        ptr_table->SL_IID_PLAY = dlsym(dlh, "SL_IID_PLAY");
        ptr_table->SL_IID_ENGINE = dlsym(dlh, "SL_IID_ENGINE");
    }

    // can't close dlh as that will unload libOpenSLES

    return (ptr_table->slCreateEngine &&
            ptr_table->SL_IID_ANDROIDSIMPLEBUFFERQUEUE &&
            ptr_table->SL_IID_ANDROIDCONFIGURATION &&
            ptr_table->SL_IID_RECORD &&
            ptr_table->SL_IID_PLAY &&
            ptr_table->SL_IID_ENGINE) ? PJ_SUCCESS : PJ_ENOTFOUND;
}

static JavaVM *
get_java_vm(void)
{
    jni_get_created_java_vms_t jni_get_created_java_vms = NULL;
    JavaVM *jvms[8] = { NULL, };
    jsize n_jvms = 0;
    void *dlh = NULL;

    // hope to $DEITY there's only one JavaVM created
    // it looks like we don't have a library with a stub
    // for this, so... linker fail!  have to use dlopen()
    // i guess for now.  really should just provide a setter, ugh
    dlh = dlopen("/system/lib/libdvm.so", RTLD_LOCAL);
    if (!dlh) {
        dlh = dlopen("libdvm.so", RTLD_LOCAL);
        if (!dlh)
            dlh = dlopen(NULL, RTLD_LOCAL);
    }

    if (dlh) {
        jni_get_created_java_vms = dlsym(dlh, "JNI_GetCreatedJavaVMs");

        if (jni_get_created_java_vms)
            jni_get_created_java_vms((JavaVM **)&jvms, sizeof(jvms)/sizeof(jvms[0]), &n_jvms);

        // closing this should be ok since libdvm has to already be mapped
        dlclose(dlh);
    }

    return n_jvms > 0 ? jvms[0] : NULL;
}

pjmedia_aud_dev_factory *
pjmedia_android_factory(pj_pool_factory *pf)
{
    sles_lib_ptr_table_t ptr_table;
    JavaVM *jvm = NULL;

    if (detect_opensles(&ptr_table) == PJ_SUCCESS) {
        PJ_LOG(3, (THIS_FILE, "Found Android OpenSL-ES implementation"));
        return pjmedia_android_sles_factory(pf, &ptr_table);
    }

    jvm = get_java_vm();
    if (jvm) {
        PJ_LOG(3, (THIS_FILE, "Falling back to Android JNI implementation"));
        return pjmedia_android_jni_factory(pf, jvm);
    }

    PJ_LOG(1, (THIS_FILE, "FATAL: can't create Android OpenSLES driver OR JNI driver!"));
    return NULL;
}

#endif  /* PJMEDIA_AUDIO_DEV_HAS_ANDROID */
