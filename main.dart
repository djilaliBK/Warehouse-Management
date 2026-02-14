import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' hide context;
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StockFlowApp());
}

// --- Data Model ---
class Product {
  final String id;
  String name;
  int quantity;
  String? imagePath;
  String category;

  Product({
    required this.id,
    required this.name,
    required this.quantity,
    this.imagePath,
    this.category = 'General',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'quantity': quantity,
      'imagePath': imagePath,
      'category': category,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      name: map['name'],
      quantity: map['quantity'],
      imagePath: map['imagePath'],
      category: map['category'] ?? 'General',
    );
  }
}

// --- Database Service ---
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String databasePath = join(documentsDirectory.path, "stockflow_core_v2.db");
    return await openDatabase(
      databasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products(
            id TEXT PRIMARY KEY,
            name TEXT,
            quantity INTEGER,
            imagePath TEXT,
            category TEXT
          )
        ''');
      },
    );
  }

  Future<void> insertProduct(Product product) async {
    final db = await database;
    await db.insert('products', product.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateProduct(Product product) async {
    final db = await database;
    await db.update('products', product.toMap(), where: 'id = ?', whereArgs: [product.id]);
  }

  Future<void> deleteProduct(String id) async {
    final db = await database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Product>> getProducts() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('products');
    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }
}

// --- Main App Entry ---
class StockFlowApp extends StatelessWidget {
  const StockFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StockFlow Pro WMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const InventoryHomePage(),
    );
  }
}

// --- Home Page ---
class InventoryHomePage extends StatefulWidget {
  const InventoryHomePage({super.key});

  @override
  State<InventoryHomePage> createState() => _InventoryHomePageState();
}

class _InventoryHomePageState extends State<InventoryHomePage> {
  final DatabaseService _dbService = DatabaseService();
  List<Product> _products = [];
  String _searchQuery = "";
  String _selectedCategory = "All"; // التصنيف المختار
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshProducts();
  }

  Future<void> _refreshProducts() async {
    setState(() => _isLoading = true);
    final data = await _dbService.getProducts();
    setState(() {
      _products = data;
      _isLoading = false;
    });
  }

  // الحصول على قائمة التصنيفات الفريدة
  List<String> get _categories {
    final set = _products.map((p) => p.category).toSet().toList();
    set.sort();
    return ["All", ...set];
  }

  Future<void> _exportToPdf() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(level: 0, child: pw.Text("StockFlow Pro - Inventory Report")),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: ['ID', 'Product Name', 'Category', 'Quantity'],
              data: _products.map((p) => [p.id, p.name, p.category, p.quantity.toString()]).toList(),
            ),
          ];
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://sites.google.com/view/stockflow-pro-wms-privacy/%D8%A7%D9%84%D8%B5%D9%81%D8%AD%D8%A9-%D8%A7%D9%84%D8%B1%D8%A6%D9%8A%D8%B3%D9%8A%D8%A9');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not launch Privacy Policy link.")));
      }
    }
  }

  Future<void> _updateQuantity(Product product, int delta) async {
    final newQty = product.quantity + delta;
    if (newQty >= 0) {
      product.quantity = newQty;
      await _dbService.updateProduct(product);
      _refreshProducts();
    }
  }

  List<Product> get _filteredProducts {
    return _products.where((product) {
      final matchesSearch = product.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCategory = _selectedCategory == "All" || product.category == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('StockFlow Pro WMS', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _exportToPdf,
            tooltip: "Export PDF",
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.indigo),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warehouse, color: Colors.white, size: 50),
                    SizedBox(height: 10),
                    Text('Warehouse Management',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.list_alt, color: Colors.indigo),
              title: const Text('Inventory List'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('Export Report (PDF)'),
              onTap: () {
                Navigator.pop(context);
                _exportToPdf();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.blue),
              title: const Text('About App'),
              onTap: () {
                Navigator.pop(context);
                showAboutDialog(
                  context: context,
                  applicationName: "StockFlow Pro WMS",
                  applicationVersion: "1.2.0",
                  applicationIcon: const Icon(Icons.warehouse, color: Colors.indigo, size: 40),
                  children: [
                    const Text("StockFlow Pro is an efficient offline warehouse management tool designed for small to medium businesses."),
                    const SizedBox(height: 10),
                    const Text("⚠️ Important Notice:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    const Text("This application operates 100% offline. It does NOT provide cloud backup services. Your data is stored only on this device. If you delete the app or clear its data, all inventory records will be lost."),
                  ],
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip, color: Colors.blueGrey),
              title: const Text('Privacy Policy'),
              onTap: () {
                Navigator.pop(context);
                _launchPrivacyPolicy();
              },
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Version 1.2.0 (Offline)', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search items...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // شريط التصنيفات
          if (_categories.length > 1)
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: isSelected,
                      onSelected: (bool selected) {
                        setState(() => _selectedCategory = selected ? cat : "All");
                      },
                      selectedColor: Colors.indigo,
                      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                ? const Center(child: Text("No items found in stock."))
                : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.75,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _filteredProducts.length,
              itemBuilder: (context, index) {
                final product = _filteredProducts[index];
                return GridProductCard(
                  product: product,
                  onDelete: () async {
                    await _dbService.deleteProduct(product.id);
                    _refreshProducts();
                  },
                  onUpdateQuantity: (delta) => _updateQuantity(product, delta),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        onPressed: () async {
          final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddProductPage())
          );
          if (result != null && result is Product) {
            await _dbService.insertProduct(result);
            _refreshProducts();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

// --- Product Card Widget (No changes) ---
class GridProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onDelete;
  final Function(int) onUpdateQuantity;
  const GridProductCard({super.key, required this.product, required this.onDelete, required this.onUpdateQuantity});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ProductImageWidget(imagePath: product.imagePath),
                Positioned(
                  top: 4, right: 4,
                  child: CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.9),
                    radius: 14,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.close, color: Colors.red, size: 16),
                      onPressed: onDelete,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(product.category, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove, size: 18, color: Colors.indigo), onPressed: () => onUpdateQuantity(-1)),
                      Text("${product.quantity}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add, size: 18, color: Colors.indigo), onPressed: () => onUpdateQuantity(1)),
                    ],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// --- Add Product Page (No changes) ---
class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});
  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _catController = TextEditingController(text: 'General');
  String? _imagePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add New Product")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              GestureDetector(
                onTap: () async {
                  final img = await ImagePicker().pickImage(source: ImageSource.gallery);
                  if (img != null) setState(() => _imagePath = img.path);
                },
                child: Container(
                  height: 160, width: 160,
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.indigo.withOpacity(0.2))),
                  child: _imagePath == null
                      ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo, size: 40, color: Colors.indigo), Text("Select Image")])
                      : ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.file(File(_imagePath!), fit: BoxFit.cover)),
                ),
              ),
              const SizedBox(height: 30),
              TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: "Product Name", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Name is required" : null),
              const SizedBox(height: 15),
              TextFormField(controller: _qtyController, decoration: const InputDecoration(labelText: "Initial Quantity", border: OutlineInputBorder()), keyboardType: TextInputType.number),
              const SizedBox(height: 15),
              TextFormField(controller: _catController, decoration: const InputDecoration(labelText: "Category", border: OutlineInputBorder())),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity, height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      Navigator.pop(context, Product(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: _nameController.text,
                        quantity: int.tryParse(_qtyController.text) ?? 0,
                        category: _catController.text,
                        imagePath: _imagePath,
                      ));
                    }
                  },
                  child: const Text("Save Item", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// --- Image Widget (No changes) ---
class ProductImageWidget extends StatelessWidget {
  final String? imagePath;
  const ProductImageWidget({super.key, this.imagePath});
  @override
  Widget build(BuildContext context) {
    if (imagePath == null || !File(imagePath!).existsSync()) {
      return Container(color: Colors.grey.shade200, child: const Icon(Icons.inventory_2, size: 50, color: Colors.grey));
    }
    return Image.file(File(imagePath!), fit: BoxFit.cover);
  }
}