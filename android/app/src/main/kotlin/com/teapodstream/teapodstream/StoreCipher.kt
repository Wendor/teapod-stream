package com.teapodstream.teapodstream

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Encrypts what [QuickConnectStore] keeps in `filesDir`; [aad] binds a ciphertext to its file. */
internal interface StoreCipher {
    /** The IV followed by the ciphertext with its tag. */
    fun encrypt(plain: ByteArray, aad: ByteArray): ByteArray

    /** Throws when [data] wasn't made by [encrypt] with this key and [aad] (another key, a lost one, a swapped file). */
    fun decrypt(data: ByteArray, aad: ByteArray): ByteArray
}

/**
 * AES-256-GCM with a key in Android Keystore: not exportable, no user authentication (the tile and boot start without
 * the user), created on first use. A key that is gone (Keystore wiped, a backup restored on another device) makes
 * every old file undecryptable; the store then treats them as nothing saved.
 */
internal object KeystoreCipher : StoreCipher {
    private const val ALIAS = "teapod_quick_connect"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128

    private fun key(): SecretKey = synchronized(this) {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as SecretKey?) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            .apply {
                init(
                    KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setKeySize(256)
                        .setRandomizedEncryptionRequired(true)
                        .build(),
                )
            }
            .generateKey()
    }

    override fun encrypt(plain: ByteArray, aad: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, key()) }
        cipher.updateAAD(aad)
        return cipher.iv + cipher.doFinal(plain)
    }

    override fun decrypt(data: ByteArray, aad: ByteArray): ByteArray {
        require(data.size > IV_BYTES) { "too short" }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, data, 0, IV_BYTES))
        cipher.updateAAD(aad)
        return cipher.doFinal(data, IV_BYTES, data.size - IV_BYTES)
    }
}
