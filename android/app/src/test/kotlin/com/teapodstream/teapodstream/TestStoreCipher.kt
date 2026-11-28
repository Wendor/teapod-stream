package com.teapodstream.teapodstream

import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** [StoreCipher] for JVM tests: AES-GCM as [KeystoreCipher], with a key in memory ([rotate] — a lost key). */
internal object TestStoreCipher : StoreCipher {
    private var key: SecretKey = newKey()

    private fun newKey(): SecretKey = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()

    fun rotate() {
        key = newKey()
    }

    override fun encrypt(plain: ByteArray, aad: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key) }
        c.updateAAD(aad)
        return c.iv + c.doFinal(plain)
    }

    override fun decrypt(data: ByteArray, aad: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, data, 0, 12))
        c.updateAAD(aad)
        return c.doFinal(data, 12, data.size - 12)
    }
}
