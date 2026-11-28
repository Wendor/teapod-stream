package com.teapodstream.teapodstream

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SecureStorageMigrationTest {
    private val prefix = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg"
    private val keysets = listOf(
        "__androidx_security_crypto_encrypted_prefs_key_keyset__",
        "__androidx_security_crypto_encrypted_prefs_value_keyset__",
    )

    @Test
    fun anEntryWithAnEncryptedNameLeftWithoutTheFlagIsPending() {
        assertTrue(SecureStorageMigration.isPending(false, keysets + "${prefix}_profiles_v1" + "AU8zk1Lq2xFv0e=="))
    }

    @Test
    fun movedEntriesKeysetsAndMarkersAreNotPending() {
        assertFalse(
            SecureStorageMigration.isPending(
                false,
                keysets + "${prefix}_profiles_v1" + "FlutterSecureSAlgorithmKey" + "FlutterSecureSAlgorithmStorage",
            ),
        )
        assertFalse(SecureStorageMigration.isPending(false, emptyList()))
    }

    @Test
    fun theFlagEndsIt() {
        assertFalse(SecureStorageMigration.isPending(true, keysets + "AU8zk1Lq2xFv0e=="))
    }
}
