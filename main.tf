terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "test1-rg" {
  name     = "test-resources"
  location = "East US"
  tags = {
    "environment" = "test"
  }
}

resource "azurerm_virtual_network" "test1-vn" {
  name                = "test-network"
  location            = azurerm_resource_group.test1-rg.location
  resource_group_name = azurerm_resource_group.test1-rg.name
  address_space       = ["10.123.0.0/16"]

  tags = {
    "environment" = "test"
  }
}

resource "azurerm_subnet" "test1-subnet" {
  name                 = "test1-subnet"
  resource_group_name  = azurerm_resource_group.test1-rg.name
  virtual_network_name = azurerm_virtual_network.test1-vn.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "test1-sg" {
  name                = "test1-securitygroup"
  location            = azurerm_resource_group.test1-rg.location
  resource_group_name = azurerm_resource_group.test1-rg.name

  tags = {
    "environment" = "test"
  }
}

resource "azurerm_network_security_rule" "test1-test-rule" {
  name                        = "test1-test-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  # source_address_prefix       = "24.227.217.186/32"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.test1-rg.name
  network_security_group_name = azurerm_network_security_group.test1-sg.name
}

resource "azurerm_subnet_network_security_group_association" "test1-sg-assoc" {
  subnet_id                 = azurerm_subnet.test1-subnet.id
  network_security_group_id = azurerm_network_security_group.test1-sg.id
}

resource "azurerm_public_ip" "test1-ip" {
  name                = "test1-public-ip"
  resource_group_name = azurerm_resource_group.test1-rg.name
  location            = azurerm_resource_group.test1-rg.location
  allocation_method   = "Dynamic"

  tags = {
    "environment" = "test"
  }
}

resource "azurerm_network_interface" "test1-nic" {
  name                = "test1-network-interface"
  location            = azurerm_resource_group.test1-rg.location
  resource_group_name = azurerm_resource_group.test1-rg.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.test1-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.test1-ip.id
  }

  tags = {
    "environment" = "test"
  }
}

# admin_ssh_key {
#   username = "admin"
#   public_key = file("~/.ssh/test1_azure_key.pub")
#}

resource "azurerm_linux_virtual_machine" "test1-vm" {
  name                  = "test1-vm"
  resource_group_name   = azurerm_resource_group.test1-rg.name
  location              = azurerm_resource_group.test1-rg.location
  size                  = "Standard_B1ls"
  admin_username        = "adminuser"
  network_interface_ids = [azurerm_network_interface.test1-nic.id]

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/test1_azure_key.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = templatefile("${var.host_os}-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = "adminuser"
      identityfile = "~/.ssh/test1_azure_key"
    })
    interpreter = var.host_os == "linux" ? ["Powershell", "-Command"] : ["bash", "-c"]
  }
}

data "azurerm_public_ip" "test1-vm-ip_data" {
  name = azurerm_public_ip.test1-ip.name
  resource_group_name = azurerm_resource_group.test1-rg.name
}

output "public_ip_address" {
  value = "${azurerm_linux_virtual_machine.test1-vm.name}: ${data.azurerm_public_ip.test1-vm-ip_data.ip_address}"
}
