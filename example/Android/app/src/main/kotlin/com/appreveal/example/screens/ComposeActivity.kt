package com.appreveal.example.screens

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.appreveal.screen.ScreenIdentifiable

class ComposeActivity : ComponentActivity(), ScreenIdentifiable {
    override val screenKey: String = "compose.test"
    override val screenTitle: String = "Compose semantics"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                ComposeSemanticsScreen()
            }
        }
    }
}

@Composable
private fun ComposeSemanticsScreen() {
    var message by remember { mutableStateOf("") }
    var sentMessage by remember { mutableStateOf("") }
    var sendCount by remember { mutableIntStateOf(0) }
    var duplicateResult by remember { mutableStateOf("none") }

    Column(
        modifier =
            Modifier
                .fillMaxSize()
                .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = "Compose semantics test",
            style = MaterialTheme.typography.headlineSmall,
        )
        OutlinedTextField(
            value = message,
            onValueChange = { message = it },
            label = { Text("Message") },
            modifier =
                Modifier
                    .fillMaxWidth()
                    .testTag("compose.message"),
        )
        Button(
            onClick = {
                sentMessage = message
                sendCount += 1
            },
            modifier = Modifier.testTag("compose.send"),
        ) {
            Text("Send a message")
        }
        Text("Sent: $sentMessage")
        Text("Send count: $sendCount")
        Button(onClick = { duplicateResult = "first" }) {
            Text("Duplicate action")
        }
        Button(onClick = { duplicateResult = "second" }) {
            Text("Duplicate action")
        }
        Text("Duplicate result: $duplicateResult")
    }
}

@Preview(showBackground = true)
@Composable
private fun ComposeSemanticsScreenPreview() {
    MaterialTheme {
        ComposeSemanticsScreen()
    }
}
