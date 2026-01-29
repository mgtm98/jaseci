"""Factory for creating utility instances (loggers, monitoring, etc.)."""
import from typing { Any }
import from jac_scale.abstractions.logger { Logger }
import from jac_scale.config_loader { get_scale_config }

"""Factory for creating utility instances."""
class UtilityFactory {
    """Create a logger based on configuration from jac.toml.

    Reads [plugins.scale.logging] configuration and creates the appropriate
    logger instance (StandardLogger, ElasticsearchLogger, etc.).

    Returns:
        Logger instance configured from jac.toml

    Example:
        logger = UtilityFactory.create_configured_logger();
        logger.info("Application started");
    """
    static def create_configured_logger -> Logger {
        scale_config = get_scale_config();
        logging_config = scale_config.get_logging_config();
        logger_type = logging_config.get('type', 'standard');
        
        if logger_type == 'elasticsearch' {
            # Pass elasticsearch-specific config
            es_config = logging_config.get('elasticsearch', {});
            return UtilityFactory.create_logger('elasticsearch', es_config);
        } else {
            # Default to standard logger
            return UtilityFactory.create_logger('standard');
        }
    }

    """Create a logger based on type.

    Args:
        logger_type: Type of logger ('standard', 'cloudwatch', 'elasticsearch', etc.)
        config: Optional logger-specific configuration

    Returns:
        Logger instance

    Raises:
        ValueError: If logger_type is not supported
        NotImplementedError: If logger is not yet implemented

    Example:
        # For testing or explicit configuration
        logger = UtilityFactory.create_logger('elasticsearch', {
            'enabled': True,
            'hosts': 'localhost:9200'
        });
    """
    static def create_logger(
        logger_type: str = 'standard', config: (dict[str, Any] | None) = None
    ) -> Logger {
        if logger_type == 'standard' {
            import from jac_scale.utilities.loggers.standard_logger { StandardLogger }
            return StandardLogger(config=config or {});
        } elif logger_type == 'cloudwatch' {
            raise NotImplementedError("CloudWatch logger not yet implemented") ;
        } elif logger_type == 'elasticsearch' {
            import from jac_scale.utilities.loggers.elasticsearch_logger { ElasticsearchLogger }
            return ElasticsearchLogger(config=config or {});
        } else {
            raise ValueError(f"Unsupported logger type: {logger_type}") ;
        }
    }
}
