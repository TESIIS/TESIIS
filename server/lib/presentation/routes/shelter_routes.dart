// lib/presentation/routes/shelter_routes.dart

import 'package:shelf_router/shelf_router.dart';
import '../controllers/shelter_controller.dart';

Router mountShelterRoutes(ShelterController controller) {
  final router = Router();
  router.mount('/api', controller.router);
  return router;
}
