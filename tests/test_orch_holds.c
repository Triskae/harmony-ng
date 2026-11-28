/*
 * The keys held by sequence steps (orchestrator.c, hold_press() / hold_service()): one per device.
 * A background step after Switched that holds a key of another device does not release the key
 * a main step holds; a new hold on the same device releases the one before; a cancel or a new
 * transition releases them all. The test includes orchestrator.c to reach its static functions;
 * the send is a stub that records each action, and the time is the test's.
 */
#include "../payload/source/orchestrator.c"

#include <stdio.h>
#include <string.h>

/* Stubs for what orchestrator.c calls */
int g_dry_run = 0;
const cJSON *config_store_activities_acquire(cfg_snap_t **snap) { *snap = NULL; return NULL; }
void config_store_release(cfg_snap_t **snap) { *snap = NULL; }
/* the sending flag of the last state event, -1 before one */
static int s_ev_sending = -1, s_ev_count = 0;
void hub_events_emit(hub_event_type_t type, cJSON *payload) {
    if (type == HUB_EV_ACTIVITY_STATE) {
        s_ev_count++;
        s_ev_sending = cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(payload, "sending")) ? 1 : 0;
    }
    cJSON_Delete(payload);
}
int hub_events_subscribe(hub_event_sink_fn fn, void *user) { (void)fn; (void)user; return 0; }
int hw_device_bt_disconnect(const char *device_id) { (void)device_id; return 0; }
/* devices whose id starts with "bt" are Bluetooth devices */
int hw_device_bt_host(const char *device_id, char *out, size_t outlen) {
    if (strncmp(device_id, "bt", 2) != 0) return 0;
    snprintf(out, outlen, "AA:BB:CC:DD:EE:FF");
    return 1;
}
int hw_device_command_send(const char *device_id, const char *command) { (void)device_id; (void)command; return 0; }
/* records what the holds send: "<device>/<command> <action>" */
static char s_sent[64][96];
static int s_count = 0;
int hw_device_command_send_action(const char *target, int match_mode, const char *command, int action) {
    (void)match_mode;
    if (s_count < 64) snprintf(s_sent[s_count++], sizeof(s_sent[0]), "%s/%s %d", target, command, action);
    return 0;
}
int hw_ir_cancel(uint8_t ports) { (void)ports; return 0; }
void hw_ir_hold_next_press_until(uint64_t release_ms) { (void)release_ms; }
int hw_ir_send_harmony_keycode(const char *keycode, uint8_t ports, uint8_t repeats) { (void)keycode; (void)ports; (void)repeats; return 0; }
int hw_ir_send_pronto(const char *pronto_hex, uint8_t ports, uint8_t repeats) { (void)pronto_hex; (void)ports; (void)repeats; return 0; }
int orch_build_steps(const char *current_id, const char *target_id,
                     orch_step_t *main_steps, size_t max_main, size_t *main_count_out,
                     orch_bg_step_t *bg_steps, size_t max_bg, size_t *bg_count_out,
                     uint32_t *switched_at_ms, uint32_t *true_end_ms) {
    (void)current_id; (void)target_id; (void)main_steps; (void)max_main; (void)main_count_out;
    (void)bg_steps; (void)max_bg; (void)bg_count_out; (void)switched_at_ms; (void)true_end_ms;
    return -1;
}
int run_bt_saved_script(const char *type, const char *bdaddr, const char *script,
                        int gap_ms, char *out, size_t outlen) {
    (void)type; (void)bdaddr; (void)script; (void)gap_ms; (void)out; (void)outlen;
    return -1;
}

static int g_fails = 0;

static void check(int cond, const char *what) {
    printf("  %s %s\n", cond ? "PASS" : "FAIL", what);
    if (!cond) g_fails++;
}

static int sent(const char *what) {
    for (int i = 0; i < s_count; i++) {
        if (strcmp(s_sent[i], what) == 0) return 1;
    }
    return 0;
}

static orch_step_t held_step(const char *dev, const char *cmd, uint32_t hold_ms) {
    orch_step_t st;
    memset(&st, 0, sizeof(st));
    st.type = STEP_ACT_DEVICE_CMD;
    snprintf(st.device_id, sizeof(st.device_id), "%s", dev);
    snprintf(st.command_name, sizeof(st.command_name), "%s", cmd);
    st.hold_ms = hold_ms;
    return st;
}

int main(void) {
    char press[32], release[32];
    printf("[-] Keys held by sequence steps, one per device\n");

    orch_step_t tv = held_step("7", "PowerToggle", 2000), atv = held_step("9", "Home", 1000);
    s_count = 0;
    check(hold_press(&tv) == 0 && hold_press(&atv) == 0, "two devices hold a key each");
    snprintf(release, sizeof(release), "7/PowerToggle %d", HW_BTN_ACTION_RELEASE);
    check(!sent(release), "the second hold does not release the first device's key");
    check(hold_active(), "a key is held");
    check(orch_is_sending(), "the orchestrator is sending while a key is held");

    /* the hold of device 9 ends first, device 7 still holds its key */
    uint64_t t0 = get_now_ms();
    int holding = hold_service(t0 + 1500);
    snprintf(release, sizeof(release), "9/Home %d", HW_BTN_ACTION_RELEASE);
    check(sent(release), "the 1 s hold is released when its time is up");
    snprintf(release, sizeof(release), "7/PowerToggle %d", HW_BTN_ACTION_RELEASE);
    check(holding && !sent(release), "the 2 s hold goes on");

    /* a new hold on device 7 releases its key first */
    orch_step_t tv2 = held_step("7", "VolumeUp", 3000);
    s_count = 0;
    check(hold_press(&tv2) == 0, "a new hold on the same device");
    snprintf(press, sizeof(press), "7/VolumeUp %d", HW_BTN_ACTION_PRESS);
    check(s_count == 2 && strcmp(s_sent[0], release) == 0 && strcmp(s_sent[1], press) == 0,
          "it releases the device's held key, then presses");

    /* a cancel releases every held key */
    orch_step_t menu = held_step("11", "Menu", 3000);
    hold_press(&menu);
    s_count = 0;
    hold_release();
    snprintf(release, sizeof(release), "7/VolumeUp %d", HW_BTN_ACTION_RELEASE);
    char release2[32];
    snprintf(release2, sizeof(release2), "11/Menu %d", HW_BTN_ACTION_RELEASE);
    check(s_count == 2 && sent(release) && sent(release2), "a cancel releases every held key");
    check(!hold_active() && hold_service(get_now_ms()) == 0, "nothing is held after the cancel");

    /* a hold is capped at HW_HOLD_MAX_MS */
    orch_step_t long_hold = held_step("11", "Menu", 60000);
    hold_press(&long_hold);
    uint64_t t1 = get_now_ms();
    check(hold_service(t1 + HW_HOLD_MAX_MS - 100) == 1, "a long hold is still held just before 10 s");
    check(hold_service(t1 + HW_HOLD_MAX_MS + 50) == 0, "and released at 10 s");

    /* Bluetooth: hub_btstack holds one key for all hosts. A Bluetooth hold releases the other
     * Bluetooth holds first, and keeps an infrared hold. */
    hold_release();
    orch_step_t ir = held_step("7", "VolumeUp", 3000), bt1 = held_step("bt1", "Select", 3000),
                bt2 = held_step("bt2", "Home", 3000);
    hold_press(&ir);
    hold_press(&bt1);
    s_count = 0;
    check(hold_press(&bt2) == 0, "a hold on a second Bluetooth device");
    snprintf(release, sizeof(release), "bt1/Select %d", HW_BTN_ACTION_RELEASE);
    snprintf(press, sizeof(press), "bt2/Home %d", HW_BTN_ACTION_PRESS);
    check(s_count == 2 && strcmp(s_sent[0], release) == 0 && strcmp(s_sent[1], press) == 0,
          "it releases the other Bluetooth device's key first, then presses");
    snprintf(release, sizeof(release), "7/VolumeUp %d", HW_BTN_ACTION_RELEASE);
    check(!sent(release), "the infrared hold goes on");
    uint64_t t2 = get_now_ms();
    s_count = 0;
    hold_service(t2 + 3100);
    snprintf(release, sizeof(release), "bt1/Select %d", HW_BTN_ACTION_RELEASE);
    check(!sent(release), "the first Bluetooth key's time up later sends no second release");

    /* sending: the state event counts a held key like GET /api/activity, and the release of the
     * last key with nothing left to send publishes sending false */
    hold_release();
    g_queue_len = 0;
    g_bg_len = 0;
    orch_step_t ok = held_step("7", "Ok", 1000);
    hold_press(&ok);
    pthread_mutex_lock(&g_act_lock);
    set_state(ORCH_STATE_RUNNING);
    pthread_mutex_unlock(&g_act_lock);
    check(s_ev_sending == 1 && orch_is_sending(), "the state event says sending while a key is held");
    int before = s_ev_count;
    hold_service(get_now_ms() + 1100);
    check(s_ev_count == before + 1 && s_ev_sending == 0 && !orch_is_sending(),
          "the release of the last held key publishes sending false");

    if (g_fails) {
        printf("[!] %d check(s) failed\n", g_fails);
        return 1;
    }
    printf("[+] Held step keys: all checks passed\n");
    return 0;
}
