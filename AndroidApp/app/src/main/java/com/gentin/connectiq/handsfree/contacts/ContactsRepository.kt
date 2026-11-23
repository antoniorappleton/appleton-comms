package com.gentin.connectiq.handsfree.contacts

import android.Manifest
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.provider.BaseColumns
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.util.Log
import androidx.core.app.ActivityCompat
import com.gentin.connectiq.handsfree.helpers.formatPhoneNumber
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable


@Serializable
data class PhoneData(
    val id: Long,
    var raw: String,
    var normalized: String? = null,
    var formatted: String? = null,
    val label: String = "",
)

@Serializable
data class ContactData(
    @SerialName("i") val id: Int,
    @SerialName("m") var name: String,
    @SerialName("n") var number: String,
)

interface ContactsRepository {
    fun invalidatePermissions()
    fun subscribe(observer: ContentObserver)
    fun unsubscribe(observer: ContentObserver)
    fun contactsData(limit: Int): List<ContactData>
    fun displayNamesForPhoneNumber(phoneNumber: String): List<String>
    fun searchContacts(query: String, limit: Int): List<ContactData>
}

class ContactsRepositoryImpl(
    base: Context?,
    val iterateOverContacts: ((contactId: Int, displayName: String) -> Boolean) -> Unit
) : ContextWrapper(base), ContactsRepository {

    companion object {
        private val TAG = ContactsRepositoryImpl::class.java.simpleName
    }

    private val delayedObservers = ArrayList<ContentObserver>()

    override fun invalidatePermissions() {
        val hasPermission = ActivityCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_CONTACTS
        ) == PackageManager.PERMISSION_GRANTED

        if (hasPermission) {
            for (observer in delayedObservers) {
                subscribeIgnoringPermissions(observer)
            }
            delayedObservers.clear()
        }
    }

    override fun subscribe(observer: ContentObserver) {
        val hasPermission = ActivityCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_CONTACTS
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasPermission) {
            delayedObservers.add(observer)
            Log.e(TAG, "notPermittedToReadContacts")
            return
        }
        subscribeIgnoringPermissions(observer)
    }

    private fun subscribeIgnoringPermissions(observer: ContentObserver) {
        contentResolver.registerContentObserver(
            Phone.CONTENT_URI,
            true,
            observer
        )
        contentResolver.registerContentObserver(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            true,
            observer
        )
    }

    override fun unsubscribe(observer: ContentObserver) {
        delayedObservers.remove(observer)
        contentResolver.unregisterContentObserver(observer)
    }

    private fun numbersForContact(
        contactId: Int,
        @Suppress("SameParameterValue") limit: Int
    ): ArrayList<String> {
        val numbers = ArrayList<String>()
        val phonesCursor = contentResolver.query(
            Phone.CONTENT_URI,
            arrayOf(
                Phone._ID,
                Phone.NUMBER,
                Phone.NORMALIZED_NUMBER
            ),
            "${Phone.CONTACT_ID} = ?",
            arrayOf("$contactId"),
            null
        )
        phonesCursor?.apply {
            val phoneIDColumn = getColumnIndex(Phone._ID)
            val phoneNumberColumn = getColumnIndex(Phone.NUMBER)
            val normalizedPhoneNumberColumn = getColumnIndex(Phone.NORMALIZED_NUMBER)
            val phoneDataList = ArrayList<PhoneData>()
            while (moveToNext()) {
                val phoneID = getLong(phoneIDColumn)
                val phoneNumber = getString(phoneNumberColumn)
                val phoneData = PhoneData(phoneID, phoneNumber)
                val normalizedPhoneNumber = getString(normalizedPhoneNumberColumn)
                normalizedPhoneNumber?.let {
                    phoneData.normalized = it
                    phoneData.formatted = formatPhoneNumber(it)
                }
                phoneDataList.add(phoneData)
                if (phoneDataList.size >= limit) {
                    break
                }
            }
            close()

            if (phoneDataList.isNotEmpty()) {
                val phoneData = phoneDataList[0]
                val number = phoneData.normalized ?: phoneData.raw
                numbers.add(number)
            }
        }
        return numbers
    }

    override fun contactsData(limit: Int): List<ContactData> {
        val contacts = ArrayList<ContactData>()
        iterateOverContacts { contactId, displayName ->
            val numbers = numbersForContact(contactId, 1)
            if (numbers.isNotEmpty()) {
                val number = numbers[0]
                contacts.add(ContactData(contactId, displayName, number))
                return@iterateOverContacts contacts.size < limit
            }
            true
        }
        return contacts
    }

    override fun displayNamesForPhoneNumber(phoneNumber: String): List<String> {
        val displayNames = ArrayList<String>()
        // https://stackoverflow.com/a/7967182/1859783
        val uri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            Uri.encode(phoneNumber)
        )
        val contactLookup = contentResolver.query(
            uri, arrayOf(
                BaseColumns._ID,
                ContactsContract.PhoneLookup.DISPLAY_NAME
            ), null, null, null
        )
        contactLookup?.apply {
            val displayNameColumn = getColumnIndex(ContactsContract.Data.DISPLAY_NAME)
            while (moveToNext()) {
                val displayName = getString(displayNameColumn)
                displayNames.add(displayName)
            }
            close()
        }
        return displayNames
    }

    // All phone numbers of the contacts whose name (or number) matches [query], by name.
    // A contact with several numbers is listed once per number, with the number type in the name.
    override fun searchContacts(query: String, limit: Int): List<ContactData> {
        val uri = Uri.withAppendedPath(Phone.CONTENT_FILTER_URI, Uri.encode(query))
        val cursor = contentResolver.query(
            uri,
            arrayOf(
                Phone.CONTACT_ID,
                Phone.DISPLAY_NAME,
                Phone.NUMBER,
                Phone.NORMALIZED_NUMBER,
                Phone.TYPE,
                Phone.LABEL
            ),
            null,
            null,
            "${Phone.DISPLAY_NAME} COLLATE LOCALIZED ASC"
        ) ?: return emptyList()

        data class Match(val contactId: Int, val name: String, val number: String, val label: String)

        val matches = ArrayList<Match>()
        val seen = HashSet<String>()
        cursor.use {
            val idColumn = it.getColumnIndex(Phone.CONTACT_ID)
            val nameColumn = it.getColumnIndex(Phone.DISPLAY_NAME)
            val numberColumn = it.getColumnIndex(Phone.NUMBER)
            val normalizedColumn = it.getColumnIndex(Phone.NORMALIZED_NUMBER)
            val typeColumn = it.getColumnIndex(Phone.TYPE)
            val labelColumn = it.getColumnIndex(Phone.LABEL)
            while (it.moveToNext() && matches.size < limit) {
                val contactId = it.getInt(idColumn)
                val name = it.getString(nameColumn) ?: continue
                val number = it.getString(normalizedColumn) ?: it.getString(numberColumn) ?: continue
                // The same number may be stored twice (e.g. in two accounts).
                if (!seen.add("$contactId $number")) {
                    continue
                }
                val label = Phone.getTypeLabel(resources, it.getInt(typeColumn), it.getString(labelColumn))
                matches.add(Match(contactId, name, number, "$label"))
            }
        }
        val numbersPerContact = matches.groupingBy { it.contactId }.eachCount()
        return matches.map {
            val name = if ((numbersPerContact[it.contactId] ?: 0) > 1) "${it.name} (${it.label})" else it.name
            ContactData(it.contactId, name, it.number)
        }
    }
}
