resource "azurerm_resource_group" "rg" {
  name     = "rg-mc-bedrock-lab"
  location = "eastus2"
}

resource "azurerm_storage_account" "sa" {
  name                     = "mclabstorageacctf"
  account_kind             = "StorageV2"
  account_replication_type = "LRS"
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  location                 = azurerm_resource_group.rg.location
}

resource "azurerm_storage_share" "share" {
  name               = "minecraft-data"
  quota              = 10
  storage_account_id = azurerm_storage_account.sa.id
}


resource "azurerm_container_group" "aci" {
  name                = "aci-mc-bedrock-lab"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  ip_address_type     = "Public"
  dns_name_label      = "acimclab"
  restart_policy      = "Always"
  container {
    name   = "minecraft"
    image  = "itzg/minecraft-bedrock-server:stable"
    cpu    = 2
    memory = 4

    dynamic "ports" {
      for_each = range(19140, 19143)
      content {
        port     = ports.value
        protocol = "UDP"
      }
    }
    ports {
      port     = 19132
      protocol = "TCP"
    }
    environment_variables = {
      EULA           = "TRUE"
      SERVER_NAME    = "lab-server"
      GAMEMODE       = "creative"
      DIFFICULTY     = "normal"
      MAX_PLAYERS    = "5"
      LEVEL_NAME     = "terraform-world"
      VIEW_DISTANCE  = "16"
      ALLOW_CHEATS   = "false"
      ONLINE_MODE    = "false"
      SERVER_PORT    = "19132"
      SERVER_PORT_V6 = "19133"
      ALLOW_LIST     = "false"
      FORCE_GAMEMODE = "true"
    }
    volume {
      name                 = "minecraft-volume"
      storage_account_name = azurerm_storage_account.sa.name
      mount_path           = "/data"
      storage_account_key  = azurerm_storage_account.sa.primary_access_key
      share_name           = azurerm_storage_share.share.name
    }

    liveness_probe {
      exec                  = ["sh", "-c", "grep -qE ':4ABC [0-9A-F]+:0000 0A' /proc/net/tcp /proc/net/tcp6"]
      initial_delay_seconds = 120
      period_seconds        = 30
      failure_threshold     = 3
      timeout_seconds       = 5
    }

  }
}
