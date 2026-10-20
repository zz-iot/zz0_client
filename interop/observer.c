/* Independent observer: eProsima XRCE session and Micro-CDR decoding. */
#include <uxr/client/client.h>
#include <ucdr/microcdr.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int received;
static void on_topic(uxrSession *s, uxrObjectId object, uint16_t request,
                     uxrStreamId stream, ucdrBuffer *cdr, uint16_t length, void *args)
{
    (void)s; (void)object; (void)request; (void)stream; (void)length; (void)args;
    uint32_t counter, size;
    char board[17]; uint8_t data[8];
    if (ucdr_deserialize_uint32_t(cdr, &counter) &&
        ucdr_deserialize_string(cdr, board, sizeof(board)) &&
        ucdr_deserialize_sequence_uint8_t(cdr, data, sizeof(data), &size) &&
        counter == 42 && strcmp(board, "zig") == 0 && size == 3 &&
        memcmp(data, (uint8_t[]){1,2,3}, 3) == 0) received = 1;
}
static void expect_status(uxrSession *s, uint16_t request)
{
    uint8_t status = 0xff;
    if (!uxr_run_session_until_all_status(s, 3000, &request, &status, 1) || status != UXR_STATUS_OK) {
        fprintf(stderr, "observer create %u failed: %u\n", request, status); exit(1);
    }
}
int main(int argc, char **argv)
{
    if (argc != 2) return 2;
    uxrUDPTransport transport;
    if (!uxr_init_udp_transport(&transport, UXR_IPv4, "127.0.0.1", argv[1])) return 1;
    uxrSession session;
    uxr_init_session(&session, &transport.comm, 0x55667788);
    uxr_set_topic_callback(&session, on_topic, NULL);
    if (!uxr_create_session(&session)) return 1;
    uint8_t output[512];
    uxrStreamId out = uxr_create_output_best_effort_stream(&session, output, sizeof(output));
    uxrStreamId in = uxr_create_input_best_effort_stream(&session);
    uxrObjectId p = uxr_object_id(1, UXR_PARTICIPANT_ID);
    uxrObjectId t = uxr_object_id(1, UXR_TOPIC_ID);
    uxrObjectId sub = uxr_object_id(1, UXR_SUBSCRIBER_ID);
    uxrObjectId r = uxr_object_id(1, UXR_DATAREADER_ID);
    expect_status(&session, uxr_buffer_create_participant_ref(&session, out, p, 0, "MyLibrary::CounterParticipant", UXR_REPLACE));
    expect_status(&session, uxr_buffer_create_topic_ref(&session, out, t, p, "MyLibrary::CounterStatusTopic", UXR_REPLACE));
    expect_status(&session, uxr_buffer_create_subscriber_xml(&session, out, sub, p, "", UXR_REPLACE));
    expect_status(&session, uxr_buffer_create_datareader_ref(&session, out, r, sub, "CounterReader", UXR_REPLACE));
    uxrDeliveryControl control = {0}; control.max_samples = UXR_MAX_SAMPLES_UNLIMITED;
    uxr_buffer_request_data(&session, out, r, in, &control);
    uxr_flash_output_streams(&session);
    puts("OBSERVER READY"); fflush(stdout);
    for (int i = 0; i < 15 && !received; ++i) uxr_run_session_time(&session, 1000);
    uxr_close_udp_transport(&transport);
    if (!received) { fputs("no valid CounterStatus received\n", stderr); return 1; }
    puts("COUNTERSTATUS RECEIVED AND VERIFIED");
    return 0;
}
