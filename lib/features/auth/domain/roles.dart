/// Roles from design doc §31, stored uppercase in users.role.
enum Role {
  owner,
  admin,
  manager,
  cashier,
  inventoryManager;

  String get storageName => name.toUpperCase();

  static Role fromStorage(String value) => Role.values.firstWhere(
    (role) => role.storageName == value,
    orElse: () => Role.cashier,
  );
  String get label => switch (this) {
    Role.owner => 'Owner',
    Role.admin => 'Admin',
    Role.manager => 'Manager',
    Role.cashier => 'Cashier',
    Role.inventoryManager => 'Inventory Manager',
  };

  String get description => switch (this) {
    Role.owner =>
      'Full control over the business, users, configuration and audit trail.',
    Role.admin => 'Same as Owner — day-to-day administration of the system.',
    Role.manager =>
      'Runs the shop: sales, refunds, exchanges, stock control and reports.',
    Role.inventoryManager =>
      'Handles stock: receiving goods, counts and adjustments; can also sell.',
    Role.cashier =>
      'Makes sales and exchanges at the register — no refunds or stock edits.',
  };
}

/// Actions a role may or may not perform. Refunds currently require manager+
/// (cashier “limited refund” scope is unresolved — see design doc §31).
enum Permission {
  makeSale,
  exchange,
  refund,
  changePrice,
  stockAdjustment,
  inventoryControl,
  productManage,
  deleteProduct,
  viewReports,
  manageUsers,
  systemConfig,
}

const Map<Role, Set<Permission>> _rolePermissions = {
  Role.owner: {
    Permission.makeSale,
    Permission.exchange,
    Permission.refund,
    Permission.changePrice,
    Permission.stockAdjustment,
    Permission.inventoryControl,
    Permission.productManage,
    Permission.deleteProduct,
    Permission.viewReports,
    Permission.manageUsers,
    Permission.systemConfig,
  },
  Role.admin: {
    Permission.makeSale,
    Permission.exchange,
    Permission.refund,
    Permission.changePrice,
    Permission.stockAdjustment,
    Permission.inventoryControl,
    Permission.productManage,
    Permission.deleteProduct,
    Permission.viewReports,
    Permission.manageUsers,
    Permission.systemConfig,
  },
  Role.manager: {
    Permission.makeSale,
    Permission.exchange,
    Permission.refund,
    Permission.changePrice,
    Permission.stockAdjustment,
    Permission.inventoryControl,
    Permission.productManage,
    Permission.deleteProduct,
    Permission.viewReports,
  },
  Role.inventoryManager: {
    Permission.makeSale,
    Permission.stockAdjustment,
    Permission.inventoryControl,
  },
  Role.cashier: {Permission.makeSale, Permission.exchange},
};

extension RoleCapabilities on Role {
  bool can(Permission permission) =>
      _rolePermissions[this]!.contains(permission);
}

extension PermissionLabel on Permission {
  String get label => switch (this) {
    Permission.makeSale => 'Make sales',
    Permission.exchange => 'Exchanges',
    Permission.refund => 'Refunds',
    Permission.changePrice => 'Change prices',
    Permission.stockAdjustment => 'Stock adjustments',
    Permission.inventoryControl => 'Add / opening stock',
    Permission.productManage => 'Edit products',
    Permission.deleteProduct => 'Delete products',
    Permission.viewReports => 'View reports',
    Permission.manageUsers => 'Manage users',
    Permission.systemConfig => 'System configuration',
  };
}
